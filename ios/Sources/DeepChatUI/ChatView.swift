import SwiftUI
import DeepChatCore

public struct ChatView: View {
    @ObservedObject var model: AppModel
    @StateObject private var attachmentDraft = AttachmentDraft()
    @StateObject private var voice = VoiceComposer()
    @State private var input = ""

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.current.messages.isEmpty {
                            emptyHint
                        }
                        ForEach(model.current.messages) { msg in
                            bubble(msg).id(msg.id)
                        }
                        if model.isStreaming {
                            HStack(spacing: 6) {
                                ProgressView().tint(Theme.dim).scaleEffect(0.7)
                                Text("正在写…").font(.system(size: Theme.size(12))).foregroundStyle(Theme.faint)
                            }
                            .padding(.leading, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .onChange(of: model.current.messages.count) { _ in
                    if let last = model.current.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            if let err = model.errorText {
                Text(err)
                    .font(.system(size: Theme.size(12.5)))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            inputBar
        }
        .background(Theme.bg)
        .onAppear {
            // 识别结束：输入框为空直接发送，已有文字就追加。
            voice.onTranscript = { text in
                let existing = input.trimmingCharacters(in: .whitespacesAndNewlines)
                if existing.isEmpty {
                    let picked = attachmentDraft.items
                    attachmentDraft.clear()
                    model.send(text, attachments: picked)
                } else {
                    input = existing + text
                }
            }
        }
        .onDisappear { voice.exitVoice() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.current.title)
                    .font(.system(size: Theme.size(16), weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(model.current.mode.label) · \(model.current.messages.count) 条")
                    .font(.system(size: Theme.size(11.5)))
                    .foregroundStyle(Theme.faint)
            }
            Spacer()
            if model.isStreaming {
                Button("停止") { model.stop() }
                    .font(.system(size: Theme.size(13), weight: .medium))
                    .foregroundStyle(Theme.danger)
            } else if !model.current.messages.isEmpty {
                Button("重新生成") { model.regenerate() }
                    .font(.system(size: Theme.size(13), weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("从一句话开始")
                .font(.system(size: Theme.size(18), weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("把要改的段落贴进来，或者只说你要写什么。历史存在本机，不上传。")
                .font(.system(size: Theme.size(13.5)))
                .foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 24)
    }

    private func bubble(_ msg: Message) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                if let reasoning = msg.reasoning, !reasoning.isEmpty {
                    ReasoningBlock(text: reasoning)
                        .padding(.bottom, 2)
                }
                Text(msg.text)
                    .font(.system(size: Theme.size(15)))
                    .foregroundStyle(msg.role == .user ? Theme.ink : Theme.ink)
                    .textSelection(.enabled)
                if !msg.attachments.isEmpty {
                    AttachmentStrip(attachments: msg.attachments)
                }
                if msg.role == .assistant && !msg.text.isEmpty {
                    ReadAloudButton(text: msg.text, tint: Theme.faint)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(msg.role == .user ? Theme.accent.opacity(0.16) : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if msg.role != .user { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            AttachmentPicker(draft: attachmentDraft)
            if voice.showsBar {
                VoicePressBar(composer: voice)
            }
            HStack(spacing: 6) {
                ForEach(WritingMode.allCases, id: \.self) { mode in
                    Button {
                        var s = model.current
                        s.mode = mode
                        model.sessions[model.currentIndex] = s
                        model.settings.defaultMode = mode
                        model.saveSettings()
                    } label: {
                        Text(mode.label)
                            .font(.system(size: Theme.size(12), weight: .medium))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(model.current.mode == mode ? Theme.accent : Theme.surface2)
                            .foregroundStyle(model.current.mode == mode ? Theme.accentInk : Theme.dim)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("写点什么…", text: $input, axis: .vertical)
                    .font(.system(size: Theme.size(15)))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VoiceMicButton(composer: voice)

                Button {
                    let text = input
                    let picked = attachmentDraft.items
                    input = ""
                    attachmentDraft.clear()
                    model.send(text, attachments: picked)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(input.isEmpty ? Theme.surface2 : Theme.accent)
                        .foregroundStyle(input.isEmpty ? Theme.faint : Theme.accentInk)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled((input.isEmpty && attachmentDraft.isEmpty) || model.isStreaming)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.bg)
    }
}

// MARK: - 思考内容

/// 模型思考过程：默认按设置折叠成一行「已深度思考」+ 展开，
/// 折叠状态每次渲染都从设置现读（`@AppStorage`），改设置对已有会话立即生效。
struct ReasoningBlock: View {
    let text: String

    @AppStorage("reasoning_collapse") private var autoCollapse = true
    @State private var expanded = false

    private var collapsed: Bool { autoCollapse && !expanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("已深度思考")
                    .font(.system(size: Theme.size(12), weight: .medium))
                    .foregroundStyle(Theme.dim)
                Spacer(minLength: 4)
                Text(collapsed ? "展开" : "收起")
                    .font(.system(size: Theme.size(12), weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }

            if !collapsed {
                Text(text)
                    .font(.system(size: Theme.size(12.5)))
                    .foregroundStyle(Theme.dim)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: autoCollapse) { _ in expanded = false }
    }
}
