import SwiftUI
import DeepChatCore

/// 导出状态：点「导出」时生成 Markdown 临时文件，界面随即出现分享按钮。
/// 只做文件准备与错误提示，不碰 `AppModel`。
public final class ExportStore: ObservableObject {

    public struct Ready: Identifiable, Equatable {
        public let id: UUID
        public let url: URL
        public let title: String
        public let messageCount: Int

        public init(id: UUID = UUID(), url: URL, title: String, messageCount: Int) {
            self.id = id
            self.url = url
            self.title = title
            self.messageCount = messageCount
        }
    }

    @Published public private(set) var ready: Ready?
    @Published public private(set) var errorText = ""

    public init() {}

    /// 单条导出。
    public func prepare(_ session: Session) {
        do {
            let url = try MarkdownExporter.shareURL(for: session)
            ready = Ready(url: url, title: session.title, messageCount: session.messages.count)
            errorText = ""
        } catch {
            ready = nil
            errorText = "导出失败：\(error.localizedDescription)"
        }
    }

    /// 全部导出：合成一份带目录的 Markdown。
    public func prepareAll(_ sessions: [Session]) {
        do {
            let url = try MarkdownExporter.shareURL(for: sessions)
            let count = sessions.reduce(0) { $0 + $1.messages.count }
            ready = Ready(url: url, title: "全部会话", messageCount: count)
            errorText = ""
        } catch {
            ready = nil
            errorText = "导出失败：\(error.localizedDescription)"
        }
    }

    public func clear() {
        ready = nil
    }
}

/// 数据页：会话列表 + 单条 / 全部导出（Markdown，走系统分享）。
/// `sessions` 由调用方传入（例如 `model.sessions`），本视图不持有 `AppModel`。
public struct DataView: View {

    public let sessions: [Session]
    @StateObject private var store: ExportStore

    public init(sessions: [Session], store: ExportStore = ExportStore()) {
        self.sessions = sessions
        _store = StateObject(wrappedValue: store)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    overview
                    if let ready = store.ready {
                        shareCard(ready)
                    }
                    if !store.errorText.isEmpty {
                        Text(store.errorText)
                            .font(.system(size: Theme.size(12.5)))
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    sessionList
                    hint
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("数据")
                .font(.system(size: Theme.size(20), weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text("\(sessions.count) 个会话")
                .font(.system(size: Theme.size(11.5)))
                .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("会话导出")
                .font(.system(size: Theme.size(12), weight: .semibold))
                .foregroundStyle(Theme.faint)
            Text("导出成 Markdown，标题、模式、逐条消息都在，通过系统分享存到「文件」或直接发给别人。")
                .font(.system(size: Theme.size(12.5)))
                .foregroundStyle(Theme.dim)
            PrimaryButton("全部导出（\(sessions.count) 个会话）") {
                store.prepareAll(sessions)
            }
            .disabled(sessions.isEmpty)
            .opacity(sessions.isEmpty ? 0.4 : 1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func shareCard(_ ready: ExportStore.Ready) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                Text("已生成")
                    .font(.system(size: Theme.size(12), weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            Text(ready.url.lastPathComponent)
                .font(.system(size: Theme.size(12.5), design: .monospaced))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(ready.title) · \(ready.messageCount) 条消息")
                .font(.system(size: Theme.size(11.5)))
                .foregroundStyle(Theme.faint)

            HStack(spacing: 8) {
                ShareLink(item: ready.url) {
                    Text("系统分享")
                        .font(.system(size: Theme.size(14), weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .foregroundStyle(Theme.accentInk)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                GhostButton("收起") { store.clear() }
                    .frame(width: 92)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("单个会话")
                .font(.system(size: Theme.size(12), weight: .semibold))
                .foregroundStyle(Theme.faint)

            if sessions.isEmpty {
                Text("还没有会话。")
                    .font(.system(size: Theme.size(13)))
                    .foregroundStyle(Theme.faint)
            }

            ForEach(sessions) { session in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.title)
                            .font(.system(size: Theme.size(14.5), weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text("\(session.mode.label) · \(session.messages.count) 条 · \(dateText(session.updatedAt))")
                            .font(.system(size: Theme.size(11.5)))
                            .foregroundStyle(Theme.faint)
                    }
                    Spacer(minLength: 8)
                    Button {
                        store.prepare(session)
                    } label: {
                        Text(store.ready?.title == session.title ? "重新导出" : "导出")
                            .font(.system(size: Theme.size(13), weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.surface2)
                            .foregroundStyle(Theme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(13)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var hint: some View {
        Text("导出文件只写在本机临时目录；分享出去之后要不要留底由你在系统面板里决定。")
            .font(.system(size: Theme.size(11.5)))
            .foregroundStyle(Theme.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}