import SwiftUI
import UniformTypeIdentifiers
import DeepChatCore

// MARK: - 导入状态

/// JSON 会话导入：选文件 → 解析预览 → 确认写入。
/// 不引用 `AppModel`：现有会话由调用方传进来，写入通过 `onImport` 回调交给上层。
public final class ImportStore: ObservableObject {

    @Published public private(set) var summary: ImportSummary?
    @Published public private(set) var errorText = ""
    @Published public private(set) var pickedName = ""
    @Published public private(set) var resultText = ""
    @Published public private(set) var busy = false

    public init() {}

    /// 选中文件后立刻解析（只读，不写任何会话）。
    public func load(url: URL, existing: [Session]) {
        busy = true
        errorText = ""
        resultText = ""
        do {
            let parsed = try SessionImporter.parse(fileURL: url, existing: existing)
            summary = parsed
            pickedName = url.lastPathComponent
        } catch {
            summary = nil
            pickedName = url.lastPathComponent
            errorText = error.localizedDescription
        }
        busy = false
    }

    /// 确认导入。没有 `onImport` 时退化为直接写本地库（重启 App 后可见）。
    public func commit(existing: [Session], onImport: (([Session]) -> Void)?) {
        guard let summary else { return }
        guard summary.hasAnything else {
            resultText = "没有可导入的新会话：解析到 \(summary.parsedSessions) 个，"
                + "跳过 \(summary.skippedDuplicates) 个重复、\(summary.skippedInvalid) 个不合格条目"
            self.summary = nil
            return
        }

        if let onImport {
            onImport(summary.imported)
        } else {
            Store.shared.saveSessions(existing + summary.imported)
        }

        var text = "导入 \(summary.imported.count) 条，跳过 \(summary.skippedDuplicates) 条重复"
        if summary.skippedInvalid > 0 { text += "，另有 \(summary.skippedInvalid) 条不合格被丢弃" }
        if summary.skippedMessages > 0 { text += "，\(summary.skippedMessages) 条消息角色无法识别已跳过" }
        if onImport == nil { text += "。已写入本机，重新打开 App 后可见" }
        resultText = text
        self.summary = nil
    }

    /// 文件选择器本身失败时的提示（不走 Importer 的错误类型）。
    public func note(_ message: String) {
        summary = nil
        resultText = ""
        errorText = message
    }

    public func reset() {
        summary = nil
        errorText = ""
        pickedName = ""
        resultText = ""
    }
}

// MARK: - 界面

/// 导入页：一个「选 JSON」按钮，解析完给预览，确认后给结果。
public struct ImportView: View {

    public let existing: [Session]
    private let onImport: (([Session]) -> Void)?

    @StateObject private var store = ImportStore()
    @State private var picking = false

    public init(existing: [Session], onImport: (([Session]) -> Void)? = nil) {
        self.existing = existing
        self.onImport = onImport
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    if let summary = store.summary {
                        previewCard(summary)
                    } else {
                        introCard
                    }
                    if !store.errorText.isEmpty {
                        errorCard
                    }
                    if !store.resultText.isEmpty {
                        resultCard
                    }
                    hint
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
        .fileImporter(isPresented: $picking,
                      allowedContentTypes: [.json, .item],
                      allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                store.load(url: url, existing: existing)
            case let .failure(error):
                store.note("选文件失败：\(error.localizedDescription)")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("导入")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            if store.busy {
                ProgressView().tint(Theme.dim).scaleEffect(0.75)
            } else {
                Text("本机解析")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("从 JSON 导入会话")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("认 Android 端导出的会话结构：`sessions` + `messages` 平铺数组，或者 `messages` 嵌在会话对象里。字段名 snake_case / camelCase 都行，时间戳毫秒、秒、ISO 字符串都认。")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.dim)
            PrimaryButton("选择 JSON 文件") {
                picking = true
            }
            Text("按会话 id 去重：同一份文件导入第二次会被整批跳过。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func previewCard(_ summary: ImportSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                Text(store.pickedName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(summary.format)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faint)

            HStack(spacing: 0) {
                stat("解析会话", "\(summary.parsedSessions)")
                divider
                stat("可导入", "\(summary.imported.count)")
                divider
                stat("跳过重复", "\(summary.skippedDuplicates)")
            }
            HStack(spacing: 0) {
                stat("消息", "\(summary.messageCount)")
                divider
                stat("不合格会话", "\(summary.skippedInvalid)")
                divider
                stat("丢弃消息", "\(summary.skippedMessages)")
            }

            if !summary.imported.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summary.imported.prefix(5)) { session in
                        Text("· \(session.title)（\(session.messages.count) 条）")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                    if summary.imported.count > 5 {
                        Text("… 还有 \(summary.imported.count - 5) 个")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }

            HStack(spacing: 8) {
                PrimaryButton("确认导入（\(summary.imported.count) 条）") {
                    store.commit(existing: existing, onImport: onImport)
                }
                GhostButton("取消") {
                    store.reset()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
                Text("导入失败")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }
            Text(store.errorText)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink)
            GhostButton("重新选择") {
                store.reset()
                picking = true
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ok)
                Text(store.resultText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.ink)
            }
            PrimaryButton("再导入一份") {
                store.reset()
                picking = true
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var hint: some View {
        Text("附件、记忆、角色卡不在这次导入范围内；只搬会话与消息。解析全程在本机，文件不会上传。")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 6)
    }
}