import SwiftUI
import DeepChatCore
#if os(iOS)
import UIKit
#endif

/// 写作页：贴一段原文，选一个动作，只要改后的段落。
public struct WriteView: View {
    @ObservedObject var model: AppModel
    @State private var draft = ""
    @State private var result = ""
    @State private var running = false

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("改写")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("贴原段落，选一个动作。只输出改后的段落，不解释。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.dim)

                TextEditor(text: $draft)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
                    .padding(12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text("在这里贴要改的段落")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.faint)
                                .padding(.top, 20)
                                .padding(.leading, 16)
                                .allowsHitTesting(false)
                        }
                    }

                HStack(spacing: 7) {
                    ForEach(Prompts.Action.allCases, id: \.self) { action in
                        Button {
                            run(action)
                        } label: {
                            Text(action.label)
                                .font(.system(size: 12.5, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.surface2)
                                .foregroundStyle(running ? Theme.faint : Theme.ink)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(running || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if running {
                    HStack(spacing: 6) {
                        ProgressView().tint(Theme.dim).scaleEffect(0.7)
                        Text("在改…").font(.system(size: 12)).foregroundStyle(Theme.faint)
                    }
                }

                if !result.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("改后")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.faint)
                        Text(result)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)

                        HStack(spacing: 8) {
                            GhostButton("复制") {
                                #if os(iOS)
                                UIPasteboard.general.string = result
                                #endif
                            }
                            GhostButton("替换原文") {
                                draft = result
                                result = ""
                            }
                            GhostButton("存为会话") {
                                var s = Session(mode: .normal)
                                s.messages = [
                                    Message(role: .user, text: draft),
                                    Message(role: .assistant, text: result)
                                ]
                                s.retitleFromFirstMessage()
                                model.sessions.insert(s, at: 0)
                                model.currentIndex = 0
                                model.persist()
                            }
                        }
                    }
                    .padding(16)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                }
                Spacer(minLength: 8)
            }
            .padding(16)
        }
        .background(Theme.bg)
    }

    private func run(_ action: Prompts.Action) {
        let key = Store.shared.apiKey() ?? ""
        guard !key.isEmpty else {
            model.errorText = "先在设置里填 API Key"
            return
        }
        running = true
        result = ""
        let text = draft
        let settings = model.settings

        Task {
            let client = ApiClient(settings: settings, apiKey: key)
            let user = action.instruction + "\n\n" + text
            do {
                let answer = try await client.complete(
                    messages: [Message(role: .user, text: user)],
                    mode: .normal
                )
                await MainActor.run {
                    result = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                    running = false
                }
            } catch {
                await MainActor.run {
                    model.errorText = error.localizedDescription
                    running = false
                }
            }
        }
    }
}