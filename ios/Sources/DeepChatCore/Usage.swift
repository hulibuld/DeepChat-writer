import Foundation
import Combine

// MARK: - 单条用量

/// 一次请求的用量：token 由本机估算（没有 tokenizer，也不引依赖）。
public struct UsageRecord: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var sessionId: UUID?
    public var model: String
    public var providerName: String
    public var promptTokens: Int
    public var completionTokens: Int
    public var createdAt: Date

    public init(id: UUID = UUID(), sessionId: UUID? = nil, model: String,
                providerName: String = "", promptTokens: Int, completionTokens: Int,
                createdAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.model = model
        self.providerName = providerName
        self.promptTokens = max(0, promptTokens)
        self.completionTokens = max(0, completionTokens)
        self.createdAt = createdAt
    }

    public var totalTokens: Int { promptTokens + completionTokens }
}

// MARK: - 聚合

/// 某一天的用量（界面「最近 7 天」的一行）。
public struct UsageDay: Identifiable, Sendable, Equatable {
    public let key: String        // yyyy-MM-dd
    public let date: Date         // 当天零点
    public let requests: Int
    public let promptTokens: Int
    public let completionTokens: Int

    public init(key: String, date: Date, requests: Int, promptTokens: Int, completionTokens: Int) {
        self.key = key
        self.date = date
        self.requests = requests
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }

    public var id: String { key }
    public var totalTokens: Int { promptTokens + completionTokens }
}

/// 一段时间窗口的合计，视图直接用。
public struct UsageSummary: Sendable, Equatable {
    public var days: [UsageDay]          // 新 → 旧
    public var requests: Int
    public var promptTokens: Int
    public var completionTokens: Int
    public var unit: String              // 「天」/「7 天」

    public init(days: [UsageDay] = [], requests: Int = 0, promptTokens: Int = 0,
                completionTokens: Int = 0, unit: String = "天") {
        self.days = days
        self.requests = requests
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.unit = unit
    }

    public var totalTokens: Int { promptTokens + completionTokens }
    public var today: UsageDay? { days.first }
    public var isEmpty: Bool { requests == 0 }
    /// 窗口里单日最高 token，视图画进度条用。
    public var peakTokens: Int { days.map(\.totalTokens).max() ?? 0 }
}

// MARK: - token 估算

/// 没有 BPE 分词，按字符类型粗估：中文 1 字 1 token，ASCII 4 字符 1 token，其余 2 字符 1 token。
/// 口径与 Android 端 `TextMetrics` / `AppState.estimateTokens` 一致。
public enum TokenEstimator {

    public static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var cjk = 0
        var ascii = 0
        var other = 0
        for scalar in text.unicodeScalars {
            if isCJK(scalar.value) {
                cjk += 1
            } else if scalar.value < 128 {
                ascii += 1
            } else {
                other += 1
            }
        }
        let asciiTokens = Int(ceil(Double(ascii) / 4.0))
        let otherTokens = Int(ceil(Double(other) / 2.0))
        return cjk + asciiTokens + otherTokens
    }

    /// 逐条估算并加上每条的结构开销（role 字段与分隔符），贴近真实计费上界。
    public static func estimate(messages: [Message]) -> Int {
        messages.reduce(0) { sum, message in
            sum + estimate(message.text) + 4 + estimate(message.role.rawValue)
        }
    }

    private static func isCJK(_ value: UInt32) -> Bool {
        (0x4E00...0x9FFF).contains(value) ||   // 基本汉字
            (0x3400...0x4DBF).contains(value) ||   // 扩展 A
            (0x3000...0x303F).contains(value) ||   // 中文标点
            (0xFF00...0xFFEF).contains(value) ||   // 全角
            (0x3040...0x30FF).contains(value) ||   // 日文假名
            (0xAC00...0xD7AF).contains(value)      // 韩文
    }
}

// MARK: - 存储

/// 用量记录的独立存储：`Application Support/DeepChat/usage.json`，与 `Store` 的会话文件并列。
public final class UsageStore: ObservableObject {

    /// 进程内共享实例：视图用 `@StateObject` 持有它，AppModel 侧调用 `record(...)` 写入后
    /// 视图会直接刷新。
    public static let shared = UsageStore()

    @Published public private(set) var records: [UsageRecord] = []

    private let folder: URL
    private let ioQueue = DispatchQueue(label: "deepchat.usage")

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

    private var fileURL: URL { folder.appendingPathComponent("usage.json") }

    // MARK: 读

    /// 重新读盘（别的实例写过之后刷新自己）。
    public func reload() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            records = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = (try? decoder.decode([UsageRecord].self, from: data)) ?? []
        records = loaded.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: 写

    /// 记一次请求：prompt 由历史消息估算，completion 由回复正文估算。
    @discardableResult
    public func record(sessionId: UUID?, model: String, providerName: String = "",
                       history: [Message], reply: String, at date: Date = Date()) -> UsageRecord {
        let row = UsageRecord(
            sessionId: sessionId,
            model: model,
            providerName: providerName,
            promptTokens: TokenEstimator.estimate(messages: history),
            completionTokens: TokenEstimator.estimate(reply),
            createdAt: date
        )
        append(row)
        return row
    }

    public func append(_ record: UsageRecord) {
        records.append(record)
        records.sort { $0.createdAt < $1.createdAt }
        save()
    }

    public func clear() {
        records = []
        save()
    }

    private func save() {
        let snapshot = records
        let url = fileURL
        ioQueue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: 汇总

    /// 最近 `days` 天（含今天）的按天合计，新 → 旧。
    public func summary(days dayCount: Int = 7, now: Date = Date(),
                        calendar: Calendar = .current) -> UsageSummary {
        let window = max(1, dayCount)
        let todayStart = calendar.startOfDay(for: now)

        var slots: [(key: String, date: Date)] = []
        for offset in 0..<window {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            slots.append((UsageStore.dayKey.string(from: date), date))
        }

        let wanted = Set(slots.map(\.key))
        var requests: [String: Int] = [:]
        var prompt: [String: Int] = [:]
        var completion: [String: Int] = [:]

        for row in records {
            let key = UsageStore.dayKey.string(from: row.createdAt)
            guard wanted.contains(key) else { continue }
            requests[key, default: 0] += 1
            prompt[key, default: 0] += row.promptTokens
            completion[key, default: 0] += row.completionTokens
        }

        let list: [UsageDay] = slots.map { slot in
            UsageDay(
                key: slot.key,
                date: slot.date,
                requests: requests[slot.key] ?? 0,
                promptTokens: prompt[slot.key] ?? 0,
                completionTokens: completion[slot.key] ?? 0
            )
        }

        return UsageSummary(
            days: list,
            requests: list.reduce(0) { $0 + $1.requests },
            promptTokens: list.reduce(0) { $0 + $1.promptTokens },
            completionTokens: list.reduce(0) { $0 + $1.completionTokens },
            unit: window > 1 ? "\(window) 天" : "今天"
        )
    }

    private static let dayKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}