import Foundation
import Combine

#if os(iOS) && canImport(Speech) && canImport(AVFAudio)
import Speech
import AVFoundation

/// 语音识别引擎：`SFSpeechRecognizer` + `AVAudioEngine`，实时部分结果。
///
/// 音频只在内存里经 tap → `SFSpeechAudioBufferRecognitionRequest` → 系统识别，
/// 不落文件、不发往本应用之外的任何服务器。识别本身可能由系统联机完成（Apple 能力）。
@MainActor
public final class VoiceInput: ObservableObject {

    public enum Status: Equatable {
        case idle
        case requesting
        case recording
        case transcribing
        case denied
        case unavailable
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var transcript: String = ""
    @Published public private(set) var elapsed: TimeInterval = 0
    @Published public private(set) var failure: String?

    public static let localeIdentifier = "zh-CN"

    /// 识别器可用性：设备没有中文识别器，或当前确实不可用时为 false（界面据此置灰）。
    public static var isSupported: Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            return false
        }
        return recognizer.isAvailable
    }

    /// 申请语音识别 + 麦克风权限；两者都给了才返回 true。
    public static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await microphoneAuthorized()
    }

    private static func microphoneAuthorized() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        }
    }

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var engine: AVAudioEngine?
    private var startedAt: Date?
    private var ticker: Timer?
    private var finalContinuation: CheckedContinuation<String, Never>?

    public init() {}

    // MARK: - 开始 / 结束

    /// 开始采集。返回 false 时看 `status`（`.denied` / `.unavailable`）。
    public func begin() async -> Bool {
        guard status == .idle || status == .denied || status == .unavailable else { return false }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: Self.localeIdentifier)) else {
            status = .unavailable
            failure = "这台设备暂时无法使用语音识别"
            return false
        }
        guard recognizer.isAvailable else {
            status = .unavailable
            failure = "这台设备暂时无法使用语音识别"
            return false
        }
        status = .requesting
        guard await Self.requestPermissions() else {
            status = .denied
            failure = "语音输入需要麦克风与语音识别权限"
            return false
        }
        self.recognizer = recognizer

        do {
            try configureAudioSession()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            self.request = request

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw VoiceError.noInput
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            self.engine = engine

            transcript = ""
            failure = nil
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal { self.resolveFinal(self.transcript) }
                    }
                    if let error {
                        self.failure = error.localizedDescription
                        self.resolveFinal(self.transcript)
                    }
                }
            }

            startedAt = Date()
            elapsed = 0
            startTicker()
            status = .recording
            return true
        } catch {
            teardown(keepTranscript: false)
            status = .unavailable
            failure = "这台设备暂时无法使用语音识别"
            return false
        }
    }

    /// 结束采集并等最终结果（最多 1.6 秒兜底），返回最终文本。
    public func end() async -> String {
        guard status == .recording else { return transcript }
        status = .transcribing
        stopAudio()
        request?.endAudio()

        let text = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            finalContinuation = cont
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                self?.resolveFinal(self?.transcript ?? "")
            }
        }
        teardown(keepTranscript: true)
        status = .idle
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 上滑取消：不取文本、不留转写。
    public func cancel() {
        task?.cancel()
        request?.endAudio()
        teardown(keepTranscript: false)
        transcript = ""
        elapsed = 0
        status = .idle
    }

    // MARK: - 内部

    private enum VoiceError: Error { case noInput }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func stopAudio() {
        if let engine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
    }

    private func teardown(keepTranscript: Bool) {
        stopTicker()
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        startedAt = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if !keepTranscript { transcript = "" }
    }

    private func resolveFinal(_ text: String) {
        guard let cont = finalContinuation else { return }
        finalContinuation = nil
        cont.resume(returning: text)
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

#else

/// 宿主侧（macOS `swift build`）占位：接口一致，永远不可用，只为让 DeepChatUI 编译通过。
@MainActor
public final class VoiceInput: ObservableObject {

    public enum Status: Equatable {
        case idle, requesting, recording, transcribing, denied, unavailable
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var transcript: String = ""
    @Published public private(set) var elapsed: TimeInterval = 0
    @Published public private(set) var failure: String?

    public static let localeIdentifier = "zh-CN"
    public static var isSupported: Bool { false }
    public static func requestPermissions() async -> Bool { false }

    public init() {}

    public func begin() async -> Bool {
        status = .unavailable
        failure = "这台设备暂时无法使用语音识别"
        return false
    }

    public func end() async -> String { transcript }
    public func cancel() { status = .idle; transcript = "" }
}

#endif