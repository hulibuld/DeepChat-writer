import Foundation

/// 会话导出：把 `[Session]` 拼成 Markdown，并落到本机临时目录供 `ShareLink` 分享。
///
/// 单条格式复用 `Api.swift` 里已有的 `Exporter.markdown(_:)`，保证「导出当前」与
/// 新的「单条导出」输出一致；这里只补「全部导出」（目录 + 逐条正文）与落盘、
/// 文件命名。不读写任何全局状态，调用方把 sessions 传进来即可。
public enum MarkdownExporter {

    // MARK: - 正文

    /// 单条会话。直接沿用已有实现的标题 / 模式 / 逐条消息排版。
    public static func exportMarkdown(_ session: Session) -> String {
        Exporter.markdown(session)
    }

    /// 全部会话：开头给导出时间、总数与目录，再逐条拼接。
    public static func exportMarkdown(_ sessions: [Session]) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        let header = "- 导出时间：\(fmt.string(from: Date()))\n"

        guard !sessions.isEmpty else {
            return "# 会话导出\n\n\(header)\n（没有可导出的会话）\n"
        }

        let messageCount = sessions.reduce(0) { $0 + $1.messages.count }
        var out = "# 会话导出\n\n"
        out += header
        out += "- 会话：\(sessions.count) 个\n"
        out += "- 消息：\(messageCount) 条\n\n"

        out += "## 目录\n\n"
        for (index, session) in sessions.enumerated() {
            out += "\(index + 1). \(session.title)（\(session.messages.count) 条）\n"
        }
        out += "\n"

        for (index, session) in sessions.enumerated() {
            out += "\n---\n\n"
            out += "> 第 \(index + 1) 个会话\n\n"
            out += exportMarkdown(session)
        }
        return out
    }

    // MARK: - 文件名

    /// 单条导出的文件名；标题里的路径分隔符与冒号换成短横，空标题兜底「会话」。
    public static func fileName(for session: Session) -> String {
        let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitize(trimmed.isEmpty ? "会话" : trimmed) + ".md"
    }

    /// 全部导出的文件名，带时间戳，避免多次导出互相覆盖。
    public static func bundleFileName(at date: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmm"
        return "DeepChat-会话导出-\(fmt.string(from: date)).md"
    }

    // MARK: - 落盘

    /// 写一份 Markdown。`folder` 省略时写进临时目录（供分享，不进「文件」App）。
    @discardableResult
    public static func write(_ markdown: String, fileName: String, to folder: URL? = nil) throws -> URL {
        let base = folder ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent(fileName.hasSuffix(".md") ? fileName : fileName + ".md")
        guard let data = markdown.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 单条导出成的临时文件，交给 `ShareLink`。
    public static func shareURL(for session: Session) throws -> URL {
        try write(exportMarkdown(session), fileName: fileName(for: session))
    }

    /// 全部导出的临时文件，交给 `ShareLink`。
    public static func shareURL(for sessions: [Session]) throws -> URL {
        try write(exportMarkdown(sessions), fileName: bundleFileName())
    }

    // MARK: - 内部

    /// 去掉文件名里不能用的字符，并把连续空白压成一个空格。
    private static func sanitize(_ name: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let parts = name.components(separatedBy: banned).filter { !$0.isEmpty }
        let joined = parts.joined(separator: "-")
        let collapsed = joined.split(separator: " ").joined(separator: " ")
        let clipped = collapsed.count > 60 ? String(collapsed.prefix(60)) : collapsed
        return clipped.isEmpty ? "会话" : clipped
    }
}