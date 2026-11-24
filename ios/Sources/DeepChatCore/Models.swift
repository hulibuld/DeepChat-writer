import Foundation

// MARK: - 消息与会话

public enum Role: String, Codable, Sendable {
    case user, assistant, system
}

public struct Message: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var role: Role
    public var text: String
    public var createdAt: Date
    public var reasoning: String?

    public init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date(), reasoning: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.reasoning = reasoning
    }
}

public struct Session: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var messages: [Message]
    public var mode: WritingMode
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String = "新会话", messages: [Message] = [],
                mode: WritingMode = .normal, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 首条用户消息的前 18 个字当标题。
    public mutating func retitleFromFirstMessage() {
        guard let first = messages.first(where: { $0.role == .user }) else { return }
        let cleaned = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        title = String(cleaned.prefix(18))
    }
}

// MARK: - 写作模式

public enum WritingMode: String, Codable, CaseIterable, Sendable {
    case normal, expert, deep, search

    public var label: String {
        switch self {
        case .normal: return "普通"
        case .expert: return "专家"
        case .deep: return "深度思考"
        case .search: return "智能搜索"
        }
    }

    /// 每个模式对应的系统提示与采样温度。四种走法共用一套对话结构，只换指令。
    public var temperature: Double {
        switch self {
        case .normal: return 0.8
        case .expert: return 0.5
        case .deep: return 0.3
        case .search: return 0.4
        }
    }
}

// MARK: - 通道与设置

public enum ProviderKind: String, Codable, Sendable {
    case openaiCompatible, deepSeek
}

public struct Provider: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var baseURL: String
    public var kind: ProviderKind
    public var model: String
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String = "DeepSeek 官方",
                baseURL: String = "https://api.deepseek.com",
                kind: ProviderKind = .deepSeek,
                model: String = "deepseek-chat",
                enabled: Bool = true) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.kind = kind
        self.model = model
        self.enabled = enabled
    }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var provider: Provider
    public var temperature: Double
    public var maxTokens: Int
    public var defaultMode: WritingMode
    public var streamEnabled: Bool
    public var speakEnabled: Bool

    public init(provider: Provider = Provider(), temperature: Double = 0.8,
                maxTokens: Int = 2048, defaultMode: WritingMode = .normal,
                streamEnabled: Bool = true, speakEnabled: Bool = false) {
        self.provider = provider
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.defaultMode = defaultMode
        self.streamEnabled = streamEnabled
        self.speakEnabled = speakEnabled
    }
}

// MARK: - 授权凭证

public struct LicenseClaims: Sendable, Equatable {
    public let code: String
    public let device: String
    public let expiresAt: Date
    public let nonce: String
    public let requiresOnline: Bool

    public init(code: String, device: String, expiresAt: Date, nonce: String, requiresOnline: Bool) {
        self.code = code
        self.device = device
        self.expiresAt = expiresAt
        self.nonce = nonce
        self.requiresOnline = requiresOnline
    }

    public var isExpired: Bool { expiresAt <= Date() }

    /// 凭证里的设备号支持通配 `*`：零售兑换码按“未绑定”签发，首次激活绑本机。
    public func matches(device current: String) -> Bool {
        device == current || device == "*"
    }
}

public enum LicenseState: Sendable, Equatable {
    case inactive
    case active(LicenseClaims)
    case expired(LicenseClaims)
    case wrongDevice(String)
    case invalid(String)
}