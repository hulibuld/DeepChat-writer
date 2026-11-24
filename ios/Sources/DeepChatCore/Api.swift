import Foundation

/// OpenAI 兼容的 /chat/completions 客户端，支持流式与非流式。
/// 只依赖 URLSession，不引第三方库；Key 从 Store（Keychain）取，不落日志。
public final class ApiClient {

    public enum ApiError: LocalizedError {
        case noKey
        case badURL
        case http(Int, String)
        case decoding(String)

        public var errorDescription: String? {
            switch self {
            case .noKey: return "还没有配置 API Key，去「设置」里填一个"
            case .badURL: return "通道地址不正确"
            case let .http(code, body):
                if code == 401 { return "Key 无效或已过期（401）" }
                if code == 429 { return "请求太频繁或额度用尽（429）" }
                return "请求失败 HTTP \(code)：\(body.prefix(120))"
            case let .decoding(msg): return "返回内容无法解析：\(msg)"
            }
        }
    }

    private let settings: AppSettings
    private let apiKey: String
    private let session: URLSession

    public init(settings: AppSettings, apiKey: String, session: URLSession = .shared) {
        self.settings = settings
        self.apiKey = apiKey
        self.session = session
    }

    private func endpoint() throws -> URL {
        guard !apiKey.isEmpty else { throw ApiError.noKey }
        var base = settings.provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/chat/completions") else { throw ApiError.badURL }
        return url
    }

    private func body(messages: [Message], stream: Bool, mode: WritingMode) throws -> Data {
        var arr: [[String: String]] = [["role": "system", "content": Prompts.system(for: mode)]]
        for m in messages where m.role != .system {
            arr.append(["role": m.role.rawValue, "content": m.text])
        }
        let payload: [String: Any] = [
            "model": settings.provider.model,
            "messages": arr,
            "temperature": mode.temperature,
            "max_tokens": settings.maxTokens,
            "stream": stream
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func request(messages: [Message], stream: Bool, mode: WritingMode) throws -> URLRequest {
        var req = URLRequest(url: try endpoint())
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try body(messages: messages, stream: stream, mode: mode)
        req.timeoutInterval = 90
        return req
    }

    /// 非流式：一次拿完整回复。
    public func complete(messages: [Message], mode: WritingMode) async throws -> String {
        let (data, response) = try await session.data(for: try request(messages: messages, stream: false, mode: mode))
        guard let http = response as? HTTPURLResponse else { throw ApiError.decoding("no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw ApiError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ApiError.decoding(String(data: data, encoding: .utf8)?.prefix(160).description ?? "")
        }
        return content
    }

    /// 流式：逐个片段回调增量文本。服务端不回 SSE 时自动退回完整响应。
    public func stream(messages: [Message], mode: WritingMode,
                       onDelta: @escaping @Sendable (String) -> Void) async throws -> String {
        let (bytes, response) = try await session.bytes(for: try request(messages: messages, stream: true, mode: mode))
        guard let http = response as? HTTPURLResponse else { throw ApiError.decoding("no response") }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw ApiError.http(http.statusCode, body)
        }

        var full = ""
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if !contentType.contains("event-stream") {
            // 通道不支持流式：把整体当一次普通响应处理。
            var raw = ""
            for try await line in bytes.lines { raw += line }
            if let data = raw.data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = root["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                onDelta(content)
                return content
            }
            throw ApiError.decoding(raw.prefix(160).description)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = root["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { continue }
            if let piece = delta["content"] as? String, !piece.isEmpty {
                full += piece
                onDelta(piece)
            }
        }
        if full.isEmpty { throw ApiError.decoding("流式返回为空") }
        return full
    }

    /// 列表模型，用于「测通」按钮。
    public func listModels() async throws -> [String] {
        var base = settings.provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/models") else { throw ApiError.badURL }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ApiError.decoding("no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw ApiError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["data"] as? [[String: Any]] else {
            return []
        }
        return list.compactMap { $0["id"] as? String }
    }
}

// MARK: - 导出

public enum Exporter {

    /// 会话导出为 Markdown：标题、时间、逐条消息。
    public static func markdown(_ session: Session) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        var out = "# \(session.title)\n\n"
        out += "- 模式：\(session.mode.label)\n"
        out += "- 创建：\(fmt.string(from: session.createdAt))\n"
        out += "- 消息：\(session.messages.count) 条\n\n---\n\n"
        for m in session.messages {
            switch m.role {
            case .user: out += "**我**\n\n\(m.text)\n\n"
            case .assistant: out += "**助手**\n\n\(m.text)\n\n"
            case .system: out += "> 系统：\(m.text)\n\n"
            }
        }
        return out
    }

    public static func write(_ text: String, name: String, to folder: URL) throws -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent(safe.hasSuffix(".md") ? safe : safe + ".md")
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}