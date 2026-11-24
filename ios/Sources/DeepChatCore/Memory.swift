import Foundation
import Combine

// MARK: - 条目类型

/// 与 Android 端 `Memory.kind` 取值一致，便于两边记忆互通。
public enum MemoryKind: String, Codable, CaseIterable, Sendable {
    case character
    case world
    case style
    case plot
    case preference
    case other

    public var label: String {
        switch self {
        case .character: return "人物"
        case .world: return "世界观"
        case .style: return "文风"
        case .plot: return "剧情"
        case .preference: return "偏好"
        case .other: return "设定"
        }
    }
}

// MARK: - 条目

/// 一条可开关的记忆：短标题 + 内容，启用才注入系统提示词。
public struct MemoryItem: Codable, Identifiable, Sendable, Equatable {

    public var id: UUID
    /// 短标题 / 键，例如「主角性格」
    public var title: String
    /// 内容，一句话或一小段
    public var content: String
    /// 启用开关
    public var enabled: Bool
    public var kind: MemoryKind
    /// 来源：manual（手写）| chat（从对话里提炼）
    public var source: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String = "", content: String = "",
                enabled: Bool = true, kind: MemoryKind = .other, source: String = "manual",
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.enabled = enabled
        self.kind = kind
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 注入用的单行：有标题写「标题：内容」，没标题就用内容本身。
    public var line: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return c }
        if c.isEmpty { return t }
        return "\(t)：\(c)"
    }

    public var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 存储

/// 记忆独立存储：`Application Support/DeepChat/memory.json`，与 `Store` 分开。
/// 视图用 `@StateObject` 自建；不要往 `AppModel` 加存储属性。
public final class MemoryStore: ObservableObject {

    @Published public private(set) var items: [MemoryItem] = []

    private let queue = DispatchQueue(label: "deepchat.memory")
    private let folder: URL

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

    private var fileURL: URL { folder.appendingPathComponent("memory.json") }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([MemoryItem].self, from: data)) ?? []
    }

    private func persist() {
        let snapshot = items
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

    public func item(id: UUID) -> MemoryItem? { items.first { $0.id == id } }

    /// 新增一条；返回 id。空条目（标题与内容都空）直接丢弃，不落库。
    @discardableResult
    public func add(_ item: MemoryItem) -> UUID? {
        guard !item.isBlank else { return nil }
        var next = item
        next.updatedAt = Date()
        items.append(next)
        persist()
        return next.id
    }

    public func update(_ item: MemoryItem) {
        guard !item.isBlank else { return }
        var next = item
        next.updatedAt = Date()
        if let index = items.firstIndex(where: { $0.id == next.id }) {
            next.createdAt = items[index].createdAt
            items[index] = next
        } else {
            items.append(next)
        }
        persist()
    }

    public func delete(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    public func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].enabled = enabled
        items[index].updatedAt = Date()
        persist()
    }

    public func toggle(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].enabled.toggle()
        items[index].updatedAt = Date()
        persist()
    }

    // MARK: 给上层拼提示词

    /// 启用中的条目，按创建时间顺序输出成行；上层直接 `joined(separator: "\n")`。
    public func activeLines() -> [String] {
        items
            .filter { $0.enabled && !$0.isBlank }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.line)
    }

    /// 拼成一段带标题的记忆块；没有启用条目时返回空串。
    public func promptBlock() -> String {
        let lines = activeLines()
        guard !lines.isEmpty else { return "" }
        var out = "【记住这些设定】"
        for (index, line) in lines.enumerated() {
            out += "\n\(index + 1). \(line)"
        }
        out += "\n（以上是已经确认的设定，回答与写作都按它来，不要和它矛盾。）"
        return out
    }

    /// 会话侧入口：把已有系统提示词和记忆块拼起来。
    /// 接法与 Persona 一致，套在外层即可（先人设、后记忆）：
    /// ```swift
    /// let system = memory.systemPrompt(
    ///     basedOn: persona.systemPrompt(basedOn: Prompts.system(for: mode))
    /// )
    /// ```
    /// 注意：persona / memory 须是视图里同一个 `@StateObject` 实例，不要再另建一份。
    public func systemPrompt(basedOn base: String) -> String {
        let block = promptBlock()
        guard !block.isEmpty else { return base }
        return base + "\n\n" + block
    }
}