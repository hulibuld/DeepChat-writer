import SwiftUI
import DeepChatCore

/// 「资料」页：把角色卡、记忆、用量、导出、通道这些次级功能收在一处，
/// 底部保留四个高频 tab，不把主界面挤成六个。
public struct MoreView: View {
    @ObservedObject var model: AppModel
    let onSelectProvider: ((Provider) -> Void)?

    public init(model: AppModel, onSelectProvider: ((Provider) -> Void)? = nil) {
        self.model = model
        self.onSelectProvider = onSelectProvider
    }

    private var sessions: [Session] { model.sessions }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    entry("酒馆", "选角色卡与世界书，一句开场直接开戏，按设定续写", "wineglass") {
                        TavernView(
                            onSend: { system, line in
                                model.beginTavern(system: system, user: line)
                            },
                            onContinue: { prompt in
                                model.beginTavern(system: "", user: prompt)
                            }
                        )
                    }
                    entry("角色卡", "人设、口癖、不会说的话，选中后写进系统提示词", "theatermasks") {
                        PersonaView()
                    }
                    entry("记忆", "人物、地名、设定单独记下来，启用后自动带进上下文", "brain.head.profile") {
                        MemoryView()
                    }
                    entry("用量", "按天累计请求次数与估算 token", "chart.bar") {
                        UsageView()
                    }
                    entry("导出", "会话导出成 Markdown，走系统分享", "square.and.arrow.up") {
                        DataView(sessions: sessions)
                    }
                    entry("通道", "多个接口地址与模型，选中一个作为当前", "point.3.connected.trianglepath.dotted") {
                        ProvidersView(onSelect: onSelectProvider)
                    }
                    entry("导入", "从 JSON 导入 Android 端导出的会话，重名或同 id 的自动跳过", "square.and.arrow.down") {
                        ImportView(existing: model.sessions) { imported in
                            model.sessions = imported + model.sessions
                            model.persist()
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .modifier(NavChrome())
        }
        .preferredColorScheme(.dark)
    }

    private func entry<Destination: View>(
        _ title: String,
        _ subtitle: String,
        _ icon: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: Theme.size(15), weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: Theme.size(12)))
                        .foregroundStyle(Theme.faint)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
/// 导航栏样式：iOS 上收紧成 inline 标题，macOS 上不动（该修饰符只在 iOS 有）。
private struct NavChrome: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationTitle("资料")
            .navigationBarTitleDisplayMode(.inline)
        #else
        content
        #endif
    }
}
