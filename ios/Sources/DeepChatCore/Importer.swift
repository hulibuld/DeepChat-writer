import Foundation

// MARK: - 结果

/// 一次导入的结果。`imported` 里只放「真正要新增」的会话，重复的已经剔掉。
public struct ImportSummary: Sendable, Equatable {

    public var imported: [Session]
    /// 文件里认出来的会话数（含重复与不合格的）
    public var parsedSessions: Int
    public var skippedDuplicates: Int
    public var skippedInvalid: Int
    public var skippedMessages: Int
    /// 识别到的结构，例如「sessions + messages 平铺数组」
    public var format: String
    public var sourceName: String

    public init(imported: [Session] = [], parsedSessions: Int = 0, skippedDuplicates: Int = 0,
                skippedInvalid: Int = 0, skippedMessages: Int = 0,
                format: String = "", sourceName: String = "") {
        self.imported = imported
        self.parsedSessions = parsedSessions
        self.skippedDuplicates = skippedDuplicates
        self.skippedInvalid = skippedInvalid
        self.skippedMessages = skippedMessages
        self.format = format
        self.sourceName = sourceName
    }

    public var messageCount: Int { imported.reduce(0) { $0 + $1.messages.count } }
    public var hasAnything: Bool { !imported.isEmpty }
}

// MARK: - 失败原因（全中文）

public enum ImportFailure: LocalizedError, Equatable {

    case unreadable(name: String)
    case empty
    case tooLarge(name: String, bytes: Int)
    case notJSON(String)
    case noSessions(String)

    public var errorDescription: String? {
        switch self {
        case let .unreadable(name):
            return "读不了「\(name)」，文件可能已被移动，或者系统没给访问权限"
        case .empty:
            return "这个文件是空的，没有可解析的内容"
        case let .tooLarge(name, bytes):
            return "「\(name)」有 \(Attachments.sizeText(bytes))，超过单个导入文件 40 MB 的上限，先拆小再导入"
        case let .notJSON(detail):
            return "这个文件不是合法 JSON：\(detail)"
        case let .noSessions(detail):
            return "JSON 能读，但里面没找到会话结构：\(detail)"
        }
    }
}

// MARK: - 导入器

/// 把 Android 端导出的会话 JSON 转成 iOS 的 `Session`。
///
/// 支持的形状（都能混着来）：
/// - `{"sessions": [...], "messages": [...]}` —— Android `Exporter.kt` 的平铺写法，
///   消息靠 `session_id` 归到会话里；
/// - `{"sessions": [{"messages": [...]}]}` 或 `{"conversations": [...]}` —— 嵌套写法；
/// - 根就是数组 —— 直接一串会话对象。
///
/// 字段名同时认 snake_case 与 camelCase；时间戳认毫秒、秒、ISO8601 字符串。
/// 无效条目不会让整次导入失败，只记进 `skippedMessages` / `skippedInvalid`。
public enum SessionImporter {

    public static let maxBytes = 40 * 1024 * 1024

    // MARK: 对外入口

    public static func parse(fileURL: URL, existing: [Session],
                             sourceName: String? = nil) throws -> ImportSummary {
        let name = sourceName ?? fileURL.lastPathComponent
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: fileURL) else {
            throw ImportFailure.unreadable(name: name)
        }
        guard data.count <= maxBytes else {
            throw ImportFailure.tooLarge(name: name, bytes: data.count)
        }
        return try parse(data, existing: existing, sourceName: name)
    }

    public static func parse(_ data: Data, existing: [Session],
                             sourceName: String = "导入.json") throws -> ImportSummary {
        guard !data.isEmpty else { throw ImportFailure.empty }

        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ImportFailure.notJSON(reason(from: error))
        }

        let extracted = try extract(root)
        let raws = extracted.sessions
        guard !raws.isEmpty else { throw ImportFailure.noSessions(extracted.hint) }

        var summaries = ImportSummary(format: extracted.format, sourceName: sourceName)
        summaries.parsedSessions = raws.count

        var seenIDs = Set(existing.map(\.id))
        var seenKeys = Set(existing.map(fingerprint))
        var imported: [Session] = []

        // 文件里自己也可能重复：同一会话出现两次只收一次。
        for index in raws.indices {
            let raw = raws[index]
            var built = Session(
                id: stableID(for: raw.externalId ?? "\(sourceName)#\(index)"),
                mode: mode(from: raw.mode),
                createdAt: raw.createdAt ?? Date(),
                updatedAt: raw.updatedAt ?? raw.createdAt ?? Date()
            )
            built.title = displayTitle(raw)

            var messages: [Message] = []
            for (order, message) in raw.messages.enumerated() {
                guard let role = role(from: message.role) else {
                    summaries.skippedMessages += 1
                    continue
                }
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty || role == .assistant else {
                    summaries.skippedMessages += 1
                    continue
                }
                messages.append(Message(
                    id: stableID(for: "\(built.id.uuidString)#\(order)#\(message.role)"),
                    role: role,
                    text: text,
                    createdAt: message.createdAt ?? built.createdAt,
                    reasoning: (message.reasoning?.isEmpty == false) ? message.reasoning : nil
                ))
            }
            built.messages = messages.sorted { $0.createdAt < $1.createdAt }

            if built.title.isEmpty { built.retitleFromFirstMessage() }
            if built.messages.isEmpty && built.title.isEmpty {
                summaries.skippedInvalid += 1
                continue
            }
            if seenIDs.contains(built.id) || seenKeys.contains(fingerprint(built)) {
                summaries.skippedDuplicates += 1
                continue
            }

            seenIDs.insert(built.id)
            seenKeys.insert(fingerprint(built))
            imported.append(built)
        }

        summaries.imported = imported.sorted { $0.updatedAt > $1.updatedAt }
        return summaries
    }

    // MARK: 结构识别

    private struct Extracted {
        var sessions: [RawSession]
        var format: String
        var hint: String
    }

    private struct RawSession {
        var externalId: String?
        var title: String
        var mode: String?
        var createdAt: Date?
        var updatedAt: Date?
        var messages: [RawMessage]
    }

    private struct RawMessage {
        var role: String
        var text: String
        var reasoning: String?
        var createdAt: Date?
        var sortIndex: Double?
    }

    private static let sessionKeys = ["sessions", "conversations", "chats", "session_list"]
    private static let messageKeys = ["messages", "msgs", "chat_messages", "message_list"]

    private static func extract(_ root: Any) throws -> Extracted {
        var sessionDicts: [[String: Any]] = []
        var flatMessages: [[String: Any]] = []
        var format = ""
        var sawSessionsKey = false

        if let array = root as? [Any] {
            let dicts = array.compactMap { $0 as? [String: Any] }
            guard !dicts.isEmpty else {
                throw ImportFailure.noSessions("根数组里都是值，不是会话对象")
            }
            sessionDicts = dicts
            format = "根数组（\(dicts.count) 个会话对象）"
        } else if let object = root as? [String: Any] {
            if let nested = firstArray(in: object, keys: sessionKeys) {
                sessionDicts = nested.compactMap { $0 as? [String: Any] }
                sawSessionsKey = true
            }
            if let messages = firstArray(in: object, keys: messageKeys) {
                flatMessages = messages.compactMap { $0 as? [String: Any] }
            }
            if sawSessionsKey {
                format = flatMessages.isEmpty
                    ? "sessions 嵌套 messages"
                    : "sessions + messages 平铺数组"
            } else if !flatMessages.isEmpty {
                format = "只有 messages 平铺数组（按 session_id 分组）"
            } else {
                let keys = object.keys.sorted().prefix(6).joined(separator: "、")
                throw ImportFailure.noSessions("顶层字段是 \(keys)，没有 sessions / conversations / messages")
            }
        } else {
            throw ImportFailure.noSessions("根既不是对象也不是数组")
        }

        var result: [RawSession] = []
        let grouping = groupMessages(flatMessages)

        for dict in sessionDicts {
            let externalId = string(in: dict, keys: ["id", "session_id", "sessionId", "uuid", "ext_id", "extId"])
            var raw = RawSession(
                externalId: externalId,
                title: string(in: dict, keys: ["title", "name", "topic"]) ?? "",
                mode: string(in: dict, keys: ["mode", "type"]),
                createdAt: date(in: dict, keys: ["created_at", "createdAt", "created", "time"]),
                updatedAt: date(in: dict, keys: ["updated_at", "updatedAt", "last_message_at", "time"]),
                messages: []
            )

            if let nested = firstArray(in: dict, keys: messageKeys) {
                raw.messages = nested.compactMap { $0 as? [String: Any] }.map(message(from:))
            } else if let key = externalId, let grouped = grouping[key] {
                raw.messages = grouped
            } else if sessionDicts.count == 1, grouping.count == 1, let only = grouping.values.first {
                raw.messages = only
            }
            result.append(raw)
        }

        // 只有 messages：按 session_id 分组，组不出来就整体当一个会话。
        if result.isEmpty && !flatMessages.isEmpty {
            if grouping.isEmpty {
                result = [RawSession(externalId: nil, title: "导入的会话", mode: nil,
                                     createdAt: nil, updatedAt: nil,
                                     messages: flatMessages.map(message(from:)))]
            } else {
                for (key, messages) in grouping {
                    result.append(RawSession(externalId: key, title: "", mode: nil,
                                             createdAt: messages.first.flatMap(\.createdAt),
                                             updatedAt: messages.last.flatMap(\.createdAt),
                                             messages: messages))
                }
            }
            if format.isEmpty { format = "按 session_id 分组的 messages" }
        }

        let hint = "认出来的条目数：sessions \(sessionDicts.count) / messages \(flatMessages.count)"
        return Extracted(sessions: result, format: format.isEmpty ? "未知结构" : format, hint: hint)
    }

    private static func groupMessages(_ flat: [[String: Any]]) -> [String: [RawMessage]] {
        var grouped: [String: [RawMessage]] = [:]
        for dict in flat {
            guard let key = string(in: dict, keys: ["session_id", "sessionId", "conversation_id", "chat_id"]) else {
                continue
            }
            grouped[key, default: []].append(message(from: dict))
        }
        for key in grouped.keys {
            grouped[key]?.sort { lhs, rhs in
                if let l = lhs.sortIndex, let r = rhs.sortIndex { return l < r }
                return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
            }
        }
        return grouped
    }

    private static func message(from dict: [String: Any]) -> RawMessage {
        RawMessage(
            role: string(in: dict, keys: ["role", "author", "sender", "from"]) ?? "",
            text: string(in: dict, keys: ["content", "text", "message", "body"]) ?? "",
            reasoning: string(in: dict, keys: ["reasoning", "reasoning_content", "think"]),
            createdAt: date(in: dict, keys: ["created_at", "createdAt", "time", "timestamp"]),
            sortIndex: number(in: dict, keys: ["sort_index", "sortIndex", "index", "order"])
        )
    }

    // MARK: 字段取值

    private static func firstArray(in dict: [String: Any], keys: [String]) -> [Any]? {
        for key in keys {
            if let array = dict[key] as? [Any] { return array }
        }
        return nil
    }

    private static func string(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            switch dict[key] {
            case let value as String:
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            case let value as NSNumber:
                return value.stringValue
            default:
                continue
            }
        }
        return nil
    }

    private static func number(in dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            switch dict[key] {
            case let value as NSNumber: return value.doubleValue
            case let value as String: return Double(value)
            default: continue
            }
        }
        return nil
    }

    private static func date(in dict: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let value = dict[key], let parsed = date(from: value) { return parsed }
        }
        return nil
    }

    private static func date(from value: Any) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            guard raw > 0 else { return nil }
            return raw > 100_000_000_000 ? Date(timeIntervalSince1970: raw / 1000) : Date(timeIntervalSince1970: raw)
        }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if let raw = Double(trimmed), raw > 0 {
                return raw > 100_000_000_000 ? Date(timeIntervalSince1970: raw / 1000) : Date(timeIntervalSince1970: raw)
            }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = iso.date(from: trimmed) { return parsed }
            iso.formatOptions = [.withInternetDateTime]
            if let parsed = iso.date(from: trimmed) { return parsed }
            for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = format
                if let parsed = formatter.date(from: trimmed) { return parsed }
            }
        }
        return nil
    }

    private static func role(from raw: String) -> Role? {
        switch raw.lowercased() {
        case "user", "human", "我":
            return .user
        case "assistant", "ai", "model", "bot", "gpt", "助手":
            return .assistant
        case "system", "system_prompt", "系统":
            return .system
        default:
            return nil
        }
    }

    private static func mode(from raw: String?) -> WritingMode {
        switch (raw ?? "").lowercased() {
        case "novel", "normal", "chat":
            return .normal
        case "tavern", "expert", "roleplay":
            return .expert
        case "deep", "thinking", "reasoner":
            return .deep
        case "search":
            return .search
        default:
            return .normal
        }
    }

    private static func displayTitle(_ raw: RawSession) -> String {
        let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return String(title.prefix(60)) }
        if let first = raw.messages.first(where: { role(from: $0.role) == .user })?.text {
            let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return String(trimmed.prefix(18)) }
        }
        return ""
    }

    private static func fingerprint(_ session: Session) -> String {
        "\(session.title)|\(Int(session.createdAt.timeIntervalSince1970))|\(session.messages.count)"
    }

    /// 由外部 id 推一个稳定的 UUID：同一份文件反复导入，算出来的 id 一样，
    /// 于是第二轮全部命中「已存在」被跳过，而不是灌一堆重复会话。
    static func stableID(for key: String) -> UUID {
        if let direct = UUID(uuidString: key) { return direct }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(16)
        var seed: UInt64 = 0xcbf29ce484222325
        for round in 0..<2 {
            var hash = seed
            for byte in key.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            hash = hash &+ UInt64(round) &* 0x9E3779B97F4A7C15
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8((hash >> UInt64(shift)) & 0xFF))
            }
            seed = hash
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40          // 版本 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80          // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func reason(from error: Error) -> String {
        let ns = error as NSError
        if let debug = ns.userInfo[NSDebugDescriptionErrorKey] as? String, !debug.isEmpty {
            return debug
        }
        return ns.localizedDescription
    }
}