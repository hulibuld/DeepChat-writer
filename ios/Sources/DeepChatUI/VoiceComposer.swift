import SwiftUI
import Combine
import DeepChatCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 触感

enum Haptics {
    #if canImport(UIKit)
    static func press() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func warn() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    #else
    static func press() {}
    static func warn() {}
    #endif
}

// MARK: - 按压状态机

/// 麦克风按压条的状态机：按住 0.3 秒才开始识别，短按只切语音态，
/// 上滑超过 64pt 进入取消区（触感反馈 + 红色提示），松手结束。
@MainActor
public final class VoiceComposer: ObservableObject {

    public enum Phase: Equatable {
        case idle          // 文字模式
        case voice         // 语音态（短按切过来，还没开始录音）
        case recording     // 正在录
        case transcribing  // 松手后等最终结果
    }

    public static let holdDelay: UInt64 = 300_000_000   // 0.3s
    public static let cancelDistance: CGFloat = 64      // 上滑阈值

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var cancelZone = false
    @Published public private(set) var notice = ""

    public let input = VoiceInput()

    /// 识别完成回调：拿到最终文本，由调用方决定「直接发送」还是「追加」。
    public var onTranscript: ((String) -> Void)?

    private var holdTask: Task<Void, Never>?
    /// 手指是否还按着：`begin()` 是异步的，按太久/松太快都要靠它判断，
    /// 否则可能出现「手指已松开但引擎刚开始录」的悬挂状态。
    private var pressing = false
    private var forwarder: AnyCancellable?

    public init() {
        // 引擎是子对象，把它的变化转发给本对象，界面才会跟着刷新。
        forwarder = input.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    public var isAvailable: Bool { VoiceInput.isSupported }
    public var partial: String { input.transcript }
    public var elapsed: TimeInterval { input.elapsed }
    public var failure: String? { input.failure }
    public var isActive: Bool { phase != .idle }
    /// 条要显示：正在录/转写、停在语音态，或者有一句要提示的失败原因。
    public var showsBar: Bool { isActive || !notice.isEmpty }

    public func pressDown() {
        guard phase == .idle || phase == .voice else { return }
        guard isAvailable else {
            notice = "这台设备暂时无法使用语音识别"
            phase = .idle
            return
        }
        notice = ""
        cancelZone = false
        pressing = true
        holdTask?.cancel()
        holdTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: VoiceComposer.holdDelay)
            guard !Task.isCancelled else { return }
            await self?.startRecording()
        }
    }

    public func dragChanged(translation: CGSize) {
        guard phase == .recording else { return }
        let zone = translation.height < -VoiceComposer.cancelDistance
        guard zone != cancelZone else { return }
        cancelZone = zone
        if zone { Haptics.warn() }
    }

    public func pressUp() {
        pressing = false
        holdTask?.cancel()
        holdTask = nil

        switch phase {
        case .recording:
            let cancelled = cancelZone
            cancelZone = false
            if cancelled {
                input.cancel()
                phase = .voice
                notice = "已取消"
            } else {
                phase = .transcribing
                Task { [weak self] in
                    guard let self else { return }
                    let text = await self.input.end()
                    self.phase = .voice
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        self.notice = "没听清，再说一次"
                    } else {
                        self.notice = ""
                        self.onTranscript?(trimmed)
                    }
                }
            }
        case .idle:
            // 短按：只切到语音态，不发任何请求。识别器不可用时停在文字模式。
            guard isAvailable else {
                notice = "这台设备暂时无法使用语音识别"
                break
            }
            phase = .voice
            Haptics.press()
        default:
            break
        }
    }

    /// 退出语音态，回到文字输入。
    public func exitVoice() {
        pressing = false
        holdTask?.cancel()
        holdTask = nil
        if phase == .recording { input.cancel() }
        cancelZone = false
        notice = ""
        phase = .idle
    }

    private func startRecording() async {
        let ok = await input.begin()
        // 抬手发生在 `begin()` 返回之前：立刻收掉，不留在录音态。
        guard pressing else {
            if ok { input.cancel() }
            if phase != .idle { phase = .voice }
            return
        }
        switch input.status {
        case .denied:
            notice = "语音输入需要麦克风与语音识别权限"
            phase = .idle
        case .unavailable:
            notice = "这台设备暂时无法使用语音识别"
            phase = .idle
        default:
            if ok {
                phase = .recording
            } else {
                notice = "这台设备暂时无法使用语音识别"
                phase = .idle
            }
        }
    }
}

// MARK: - 按压条

/// 录音 / 转写期间显示在输入框上方：计时、实时部分文本、松手提示。
public struct VoicePressBar: View {
    @ObservedObject var composer: VoiceComposer
    public init(composer: VoiceComposer) { self.composer = composer }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(timeText)
                    .font(.system(size: Theme.size(12.5), weight: .semibold, design: .monospaced))
                    .foregroundStyle(composer.cancelZone ? Theme.danger : Theme.dim)
                Spacer(minLength: 8)
                Text(hint)
                    .font(.system(size: Theme.size(12.5), weight: .semibold))
                    .foregroundStyle(composer.cancelZone ? Theme.danger : (composer.phase == .transcribing ? Theme.accent : Theme.faint))
                if composer.phase == .voice {
                    Button("改用文字") { composer.exitVoice() }
                        .font(.system(size: Theme.size(12), weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
            }

            Text(bodyText)
                .font(.system(size: Theme.size(13)))
                .foregroundStyle(composer.cancelZone ? Theme.danger : Theme.dim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !composer.notice.isEmpty {
                Text(composer.notice)
                    .font(.system(size: Theme.size(11.5)))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(composer.cancelZone ? Theme.danger.opacity(0.6) : Color.clear, lineWidth: 1)
        )
    }

    /// `0:07` 这种格式。
    private var timeText: String {
        let total = Int(composer.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var hint: String {
        switch composer.phase {
        case .recording: return composer.cancelZone ? "松手取消" : "松手结束"
        case .transcribing: return "正在转写…"
        default: return "按住说话，上滑取消"
        }
    }

    private var bodyText: String {
        if composer.phase == .transcribing { return "正在转写…" }
        return composer.partial.isEmpty ? "按住说话，上滑取消" : composer.partial
    }
}

// MARK: - 麦克风键

/// 输入区右侧的圆形麦克风键：按住说话、上滑取消、短按切语音态。
public struct VoiceMicButton: View {
    @ObservedObject var composer: VoiceComposer
    public init(composer: VoiceComposer) { self.composer = composer }

    @State private var pressing = false

    public var body: some View {
        let active = composer.phase == .recording || composer.phase == .voice
        Image(systemName: composer.phase == .recording ? "waveform" : "mic.fill")
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 40, height: 40)
            .background(active ? Theme.accent : Theme.surface2)
            .foregroundStyle(active ? Theme.accentInk : Theme.dim)
            .clipShape(Circle())
            .opacity(composer.isAvailable ? 1 : 0.35)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !pressing {
                            pressing = true
                            composer.pressDown()
                        }
                        composer.dragChanged(translation: value.translation)
                    }
                    .onEnded { _ in
                        pressing = false
                        composer.pressUp()
                    }
            )
    }
}