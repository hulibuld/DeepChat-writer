import SwiftUI
import DeepChatCore

public struct ChatView: View {
    @ObservedObject var model: AppModel
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
                                Text("正在写…").font(.system(size: 12)).foregroundStyle(Theme.faint)
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
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            inputBar
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.current.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(model.current.mode.label) · \(model.current.messages.count) 条")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faint)
            }
            Spacer()
            if model.isStreaming {
                Button("停止") { model.stop() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.danger)
            } else if !model.current.messages.isEmpty {
                Button("重新生成") { model.regenerate() }
                    .font(.system(size: 13, weight: .medium))
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("把要改的段落贴进来，或者只说你要写什么。历史存在本机，不上传。")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 24)
    }

    private func bubble(_ msg: Message) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(msg.text)
                    .font(.system(size: 15))
                    .foregroundStyle(msg.role == .user ? Theme.ink : Theme.ink)
                    .textSelection(.enabled)
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
                            .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    let text = input
                    input = ""
                    model.send(text)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(input.isEmpty ? Theme.surface2 : Theme.accent)
                        .foregroundStyle(input.isEmpty ? Theme.faint : Theme.accentInk)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(input.isEmpty || model.isStreaming)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.bg)
    }
}