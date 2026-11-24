import Foundation
import Combine

/// 一条世界书条目：触发词命中了才注入；触发词为空视为常驻。
/// 字段与 Android 端 `PersonaWorldEntry` 对齐（keys 在这里是数组，落盘也是数组）。
public struct WorldbookEntry: Codable, Identifiable, Sendable, Equatable {

    public var id: UUID
    /// 触发词；空数组 = 每轮常驻。
    public var keys: [String]
    public var content: String
    public var enabled: Bool
    /// 注入顺序，小的在前。
    public var order: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), keys: [String] = [], content: String = "",
                enabled: Bool = true, order: Int = 0,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.keys = keys
        self.content = content
        self.enabled = enabled
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: 便捷读写

    /// 触发词的编辑态文本：逗号分隔，中英文逗号都接受。
    public var keysText: String {
        get { keys.joined(separator: ", ") }
        set { keys = WorldbookEntry.parseKeys(newValue) }
    }

    public static func parseKeys(_ raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "、", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 常驻条目：没有触发词。
    public var isAlways: Bool { keys.isEmpty }

    public var isBlank: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && keys.isEmpty
    }

    public var title: String {
        keys.isEmpty ? "常驻条目" : keys.joined(separator: "、")
    }

    /// 命中判定：常驻恒 true；否则任一触发词出现在 text 里（忽略大小写）。
    public func matches(_ text: String) -> Bool {
        if isAlways { return true }
        let haystack = text.lowercased()
        return keys.contains { key in
            let needle = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return !needle.isEmpty && haystack.contains(needle)
        }
    }
}

// MARK: - 存储

/// 世界书独立存储：`Application Support/DeepChat/worldbook.json`，写法照 `Store.swift`。
/// 视图里用 `@StateObject` 自建；不要往 `AppModel` 加存储属性。
public final class WorldbookStore: ObservableObject {

    @Published public private(set) var entries: [WorldbookEntry] = []

    private let queue = DispatchQueue(label: "deepchat.worldbook")
    private let folder: URL

    /// 单次注入的字数上限，与 Android 端「酒馆」门的世界书预算一致。
    public static let defaultCharBudget = 2400

    public init(folder: URL? = nil) {
        if let folder {
            self.folder = folder
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.folder = base.appendingPathComponent("DeepChat", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        load()
    }

    // MARK: 落盘

    private var fileURL: URL { folder.appendingPathComponent("worldbook.json") }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([WorldbookEntry].self, from: data)) ?? []
    }

    private func persist() {
        let snapshot = entries
        let url = fileURL
        queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: 增删改查

    public func entry(id: UUID) -> WorldbookEntry? { entries.first { $0.id == id } }

    public func contains(_ id: UUID) -> Bool { entries.contains { $0.id == id } }

    /// 新增；内容与触发词都空时丢弃。返回 id。
    @discardableResult
    public func add(_ entry: WorldbookEntry) -> UUID? {
        guard !entry.isBlank else { return nil }
        var next = entry
        next.updatedAt = Date()
        entries.append(next)
        sort()
        persist()
        return next.id
    }

    public func update(_ entry: WorldbookEntry) {
        guard !entry.isBlank else { return }
        var next = entry
        next.updatedAt = Date()
        if let index = entries.firstIndex(where: { $0.id == next.id }) {
            next.createdAt = entries[index].createdAt
            entries[index] = next
        } else {
            entries.append(next)
        }
        sort()
        persist()
    }

    public func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    public func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].enabled = enabled
        entries[index].updatedAt = Date()
        persist()
    }

    public func toggle(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].enabled.toggle()
        entries[index].updatedAt = Date()
        persist()
    }

    public func isEnabled(_ id: UUID) -> Bool { entry(id: id)?.enabled ?? false }

    public func setOrder(_ order: Int, id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].order = order
        entries[index].updatedAt = Date()
        sort()
        persist()
    }

    private func sort() {
        entries.sort { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.createdAt < rhs.createdAt
        }
    }

    // MARK: 匹配

    /// 取 text 末尾 `scanDepth` 条非空行作为扫描窗口；scanDepth <= 0 视为全文。
    public static func scanWindow(_ text: String, scanDepth: Int) -> String {
        guard scanDepth > 0 else { return text }
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count > scanDepth else { return lines.joined(separator: "\n") }
        return lines.suffix(scanDepth).joined(separator: "\n")
    }

    /// 命中的启用条目（含常驻），按 order 排序。
    public func match(in text: String) -> [WorldbookEntry] {
        entries.filter { $0.enabled && $0.matches(text) }
    }

    /// 拼世界书块。`text` 传最近对话原文，`scanDepth` 传要扫的行数（末尾若）。
    /// `forced` 里给的条目无论触发词是否命中都注入（酒馆页手动勾选的那些）。
    /// 无命中返回空字符串 —— 上层据此不追加任何内容。
    public func prompt(matching text: String, scanDepth: Int, forced: [UUID] = []) -> String {
        let window = WorldbookStore.scanWindow(text, scanDepth: scanDepth)
        var picked = entries.filter { entry in
            guard entry.enabled else { return false }
            return forced.contains(entry.id) || entry.matches(window)
        }
        // 去重（勾选又命中）
        var seen = Set<UUID>()
        picked = picked.filter { seen.insert($0.id).inserted }
        picked.sort { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.createdAt < rhs.createdAt
        }
        guard !picked.isEmpty else { return "" }

        var lines: [String] = []
        var used = 0
        for entry in picked {
            let body = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            if used + body.count > WorldbookStore.defaultCharBudget { continue }
            lines.append(body)
            used += body.count
        }
        guard !lines.isEmpty else { return "" }

        var out = "【这个世界】"
        for (index, line) in lines.enumerated() {
            out += "\n\(index + 1). \(line)"
        }
        let ref = lines.count <= 4
            ? (1...lines.count).map(String.init).joined(separator: "、")
            : "1 到 \(lines.count)"
        out += "\n（说到相关的事，就按上面第 \(ref) 条来。）"
        return out
    }
}