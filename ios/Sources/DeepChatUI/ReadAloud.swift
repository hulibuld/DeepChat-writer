import SwiftUI
import AVFoundation

/// 朗读控制器：`AVSpeechSynthesizer` 读一段文本，支持开始 / 暂停 / 继续 / 停止与语速调节。
/// iOS 不申请麦克风等权限，系统语音随 App 一起可用；状态都由合成器回调刷新。
public final class ReadAloudController: NSObject, ObservableObject {

    @Published public private(set) var isSpeaking = false
    @Published public private(set) var isPaused = false
    @Published public private(set) var currentText = ""
    /// 系统语速 0.0–1.0，默认 0.5。界面按 0.2–0.8 给滑杆。
    @Published public var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    private let synthesizer = AVSpeechSynthesizer()

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 去掉不适合念出来的标记（搜索引用编号），并压掉首尾空白。
    public static func cleaned(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(
            of: "\\[citation:\\d+\\]",
            with: "",
            options: .regularExpression
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canResume: Bool { isPaused }

    /// 从这段文本开始读。正在读其它内容时先停下再换。
    public func speak(_ text: String) {
        let clean = Self.cleaned(text)
        guard !clean.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN") ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = 1.0
        currentText = clean
        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
    }

    public func pause() {
        guard synthesizer.isSpeaking, !synthesizer.isPaused else { return }
        if synthesizer.pauseSpeaking(at: .immediate) {
            isPaused = true
            isSpeaking = true
        }
    }

    public func resume() {
        guard synthesizer.isPaused else { return }
        if synthesizer.continueSpeaking() {
            isPaused = false
            isSpeaking = true
        }
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        currentText = ""
    }

    /// 消息行上的按钮：正在读就停，没读就开始。
    public func toggle(_ text: String) {
        if isSpeaking {
            stop()
        } else {
            speak(text)
        }
    }

    private func syncState() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSpeaking = self.synthesizer.isSpeaking
            self.isPaused = self.synthesizer.isPaused
            if !self.synthesizer.isSpeaking {
                self.currentText = ""
            }
        }
    }
}

extension ReadAloudController: AVSpeechSynthesizerDelegate {

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                  didStart utterance: AVSpeechUtterance) {
        syncState()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                  didPause utterance: AVSpeechUtterance) {
        syncState()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                  didContinue utterance: AVSpeechUtterance) {
        syncState()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                  didFinish utterance: AVSpeechUtterance) {
        syncState()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                  didCancel utterance: AVSpeechUtterance) {
        syncState()
    }
}

// MARK: - 消息行上的朗读按钮

/// 放在气泡旁边的紧凑按钮：朗读中显示暂停图标，点一下停。
public struct ReadAloudButton: View {

    public let text: String
    public var tint: Color
    @StateObject private var controller = ReadAloudController()

    public init(text: String, tint: Color = Theme.dim) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Button {
            controller.toggle(text)
        } label: {
            Image(systemName: controller.isSpeaking ? "pause.circle" : "speaker.wave.2")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(controller.isSpeaking ? Theme.accent : tint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(ReadAloudController.cleaned(text).isEmpty)
    }
}

// MARK: - 朗读条

/// 完整控制条：开始 / 暂停 / 继续 / 停止 + 语速滑杆。挂在对话页或导出预览里都行。
public struct ReadAloudBar: View {

    public let text: String
    public let title: String
    @StateObject private var controller = ReadAloudController()

    public init(text: String, title: String = "朗读") {
        self.text = text
        self.title = title
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.system(size: Theme.size(12), weight: .semibold))
                    .foregroundStyle(Theme.faint)
                Spacer()
                Text(status)
                    .font(.system(size: Theme.size(11.5)))
                    .foregroundStyle(controller.isSpeaking ? Theme.ok : Theme.faint)
            }

            HStack(spacing: 8) {
                GhostButton(controller.isSpeaking ? "停止" : "开始") {
                    if controller.isSpeaking {
                        controller.stop()
                    } else {
                        controller.speak(text)
                    }
                }
                GhostButton("暂停") {
                    controller.pause()
                }
                GhostButton("继续") {
                    controller.resume()
                }
            }

            HStack(spacing: 10) {
                Text("语速")
                    .font(.system(size: Theme.size(11.5)))
                    .foregroundStyle(Theme.faint)
                Slider(value: $controller.rate, in: 0.2...0.8, step: 0.05)
                    .tint(Theme.accent)
                Text(String(format: "×%.2f", controller.rate / AVSpeechUtteranceDefaultSpeechRate))
                    .font(.system(size: Theme.size(11.5), design: .monospaced))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 46, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var status: String {
        if controller.isPaused { return "已暂停" }
        if controller.isSpeaking { return "朗读中" }
        return "未开始"
    }
}