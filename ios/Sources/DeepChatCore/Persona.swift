import Foundation
import Combine

// MARK: - 注入小节

/// 与 Android 端 `PersonaEngine.SECTION_KEYS` 同序、同 rawValue，两端卡数据可直接互通。
public enum PersonaSection: String, Codable, CaseIterable, Sendable {
    case selfIntro = "self"
    case personality
    case speechHabits
    case neverSay
    case examples
    case scene
    case greeting

    public var label: String {
        switch self {
        case .selfIntro: return "自述"
        case .personality: return "性格"
        case .speechHabits: return "口癖"
        case .neverSay: return "不会说的话"
        case .examples: return "对话示例"
        case .scene: return "场景"
        case .greeting: return "开场白"
        }
    }

    public var hint: String {
        switch self {
        case .selfIntro: return "我是谁"
        case .personality: return "说话行事方式"
        case .speechHabits: return "常说的话 / 语气"
        case .neverSay: return "绝不会说的话（防角色漂移）"
        case .examples: return "一段真实说话样例"
        case .scene: return "发生在哪里"
        case .greeting: return "第一句话怎么说"
        }
    }

    /// 默认全开：iOS 端没有「门」的概念，一张卡就一套小节。
    public static var defaults: [PersonaSection] { PersonaSection.allCases }
}

// MARK: - 角色卡

/// 一张角色卡。字段与 Android 端 `PersonaEngine.Card` 对齐（`self` 落盘键保持一致）。
public struct PersonaCard: Codable, Identifiable, Sendable, Equatable {

    public var id: UUID
    /// 角色名
    public var name: String
    /// 场景 / 身份
    public var scene: String
    /// 自述（人设主体）
    public var selfIntro: String
    public var personality: String
    /// 口头禅 / 口癖
    public var speechHabits: String
    /// 禁忌：不会说的话
    public var neverSay: String
    /// 开场白
    public var greeting: String
    /// 对话示例
    public var examples: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String = "", scene: String = "",
                selfIntro: String = "", personality: String = "", speechHabits: String = "",
                neverSay: String = "", greeting: String = "", examples: String = "",
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.scene = scene
        self.selfIntro = selfIntro
        self.personality = personality
        self.speechHabits = speechHabits
        self.neverSay = neverSay
        self.greeting = greeting
        self.examples = examples
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, scene
        case selfIntro = "self"
        case personality, speechHabits, neverSay, greeting, examples
        case createdAt, updatedAt
    }

    // MARK: 小节读写

    /// 取某一节的原文；未知节返回空串。
    public func text(for section: PersonaSection) -> String {
        switch section {
        case .selfIntro: return selfIntro
        case .personality: return personality
        case .speechHabits: return speechHabits
        case .neverSay: return neverSay
        case .examples: return examples
        case .scene: return scene
        case .greeting: return greeting
        }
    }

    /// 写某一节。视图编辑器用它回填，避免九处 switch 散在 UI 层。
    public mutating func setText(_ value: String, for section: PersonaSection) {
        switch section {
        case .selfIntro: selfIntro = value
        case .personality: personality = value
        case .speechHabits: speechHabits = value
        case .neverSay: neverSay = value
        case .examples: examples = value
        case .scene: scene = value
        case .greeting: greeting = value
        }
    }

    public var isBlank: Bool {
        PersonaSection.allCases.allSatisfy { text(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名" : trimmed
    }

    public var filledSectionCount: Int {
        PersonaSection.allCases.filter { !text(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    public var sections: [PersonaSection] {
        PersonaSection.allCases.filter { !text(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: 拼提示词

    /// 按勾选的小节拼一段人设提示词，替换 `{{char}}` / `{{user}}`。
    /// 返回空串表示这张卡没有可注入的内容（上层据此整段跳过，不要拼出空标题）。
    public func render(sections selected: [PersonaSection],
                       charName: String = "{{char}}",
                       userName: String = "{{user}}") -> String {
        let enabled = Set(selected)
        var parts: [String] = []

        for section in PersonaSection.allCases where enabled.contains(section) {
            let raw = text(for: section).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            let body = raw
                .replacingOccurrences(of: "{{char}}", with: charName)
                .replacingOccurrences(of: "{{user}}", with: userName)
            parts.append("【\(section.label)】\n\(body)")
            if section == .neverSay {
                parts.append("（以上为禁止事项，须严格遵守，不要说出这些话。）")
            }
        }

        guard !parts.isEmpty else { return "" }
        return "[人设卡：\(displayName)]\n" + parts.joined(separator: "\n")
    }
}

// MARK: - 存储

/// 角色卡独立存储：`Application Support/DeepChat/persona.json`，与 `Store` 的 sessions/settings 分开。
/// 视图用 `@StateObject` 自建；不要往 `AppModel` 加存储属性。
public final class PersonaStore: ObservableObject {

    @Published public private(set) var cards: [PersonaCard] = []
    /// 当前选中的卡；会话拼系统提示词时用它。
    @Published public private(set) var selectedID: UUID?
    /// 注入的小节；默认全开。
    @Published public private(set) var enabledSections: [PersonaSection] = PersonaSection.defaults

    private let queue = DispatchQueue(label: "deepchat.persona")
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

    private struct Payload: Codable {
        var cards: [PersonaCard]
        var selectedID: UUID?
        var sections: [PersonaSection]
    }

    private var fileURL: URL { folder.appendingPathComponent("persona.json") }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else { return }
        cards = payload.cards
        selectedID = payload.selectedID.flatMap { id in cards.contains { $0.id == id } ? id : nil }
        if !payload.sections.isEmpty { enabledSections = payload.sections }
    }

    private func persist() {
        let payload = Payload(cards: cards, selectedID: selectedID, sections: enabledSections)
        let url = fileURL
        queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(payload) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: 增删改查

    public func contains(_ id: UUID) -> Bool { cards.contains { $0.id == id } }

    public func card(id: UUID?) -> PersonaCard? {
        guard let id else { return nil }
        return cards.first { $0.id == id }
    }

    /// 新增；重名不拦，按 id 区分。新建即选中。
    @discardableResult
    public func add(_ card: PersonaCard) -> UUID {
        var next = card
        next.updatedAt = Date()
        cards.append(next)
        if selectedID == nil { selectedID = next.id }
        persist()
        return next.id
    }

    /// 按 id 更新已有卡；找不到时退化为新增。
    public func update(_ card: PersonaCard) {
        var next = card
        next.updatedAt = Date()
        if let index = cards.firstIndex(where: { $0.id == next.id }) {
            next.createdAt = cards[index].createdAt
            cards[index] = next
        } else {
            cards.append(next)
        }
        if selectedID == nil { selectedID = next.id }
        persist()
    }

    public func delete(id: UUID) {
        cards.removeAll { $0.id == id }
        if selectedID == id { selectedID = cards.first?.id }
        persist()
    }

    public func select(_ id: UUID?) {
        selectedID = id.flatMap { candidate in cards.contains { $0.id == candidate } ? candidate : nil }
        persist()
    }

    public var selectedCard: PersonaCard? { card(id: selectedID) }

    // MARK: 小节开关

    public func isEnabled(_ section: PersonaSection) -> Bool { enabledSections.contains(section) }

    public func toggle(_ section: PersonaSection) {
        if let index = enabledSections.firstIndex(of: section) {
            enabledSections.remove(at: index)
        } else {
            enabledSections.append(section)
            enabledSections.sort { lhs, rhs in
                (PersonaSection.allCases.firstIndex(of: lhs) ?? 0) < (PersonaSection.allCases.firstIndex(of: rhs) ?? 0)
            }
        }
        persist()
    }

    // MARK: 给上层拼提示词

    /// 选中的卡按当前小节开关拼出来的人设段；没有选中卡或全空时返回空串。
    public func prompt(charName: String = "{{char}}", userName: String = "{{user}}") -> String {
        guard let card = selectedCard else { return "" }
        return card.render(sections: enabledSections, charName: charName, userName: userName)
    }

    /// 会话侧入口：把已有系统提示词和角色卡段拼起来。
    /// 用法——`AppModel.send` 里把 `Prompts.system(for: mode)` 换成
    /// `PersonaStore.shared.systemPrompt(basedOn: Prompts.system(for: mode))`，
    /// 再叠一层 `MemoryStore.shared.systemPrompt(basedOn:)` 即可，无需改 `Prompts` 本身。
    public func systemPrompt(basedOn base: String,
                             charName: String = "{{char}}",
                             userName: String = "{{user}}") -> String {
        let block = prompt(charName: charName, userName: userName)
        guard !block.isEmpty else { return base }
        return base + "\n\n" + block
    }
}