import SwiftUI
import DeepChatCore

/// 应用根视图。App target 里写：
/// ```swift
/// @main struct DeepChatApp: App {
///     var body: some Scene { WindowGroup { AppRootView() } }
/// }
/// ```
public struct AppRootView: View {

    @StateObject private var model = AppModel()
    @State private var gateChecked = false

    public init() {}

    public var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if !gateChecked {
                ProgressView().tint(Theme.dim)
                    .task {
                        model.bootstrap()
                        gateChecked = true
                    }
            } else if model.licenseActive {
                MainTabView(model: model)
            } else {
                LicenseView(model: model)
            }
        }
        .preferredColorScheme(.dark)
    }
}

public struct MainTabView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case 0: ChatView(model: model)
                case 1: WriteView(model: model)
                case 2: LibraryView(model: model)
                case 3: MoreView(model: model) { provider in
                    model.settings.provider = provider
                    model.saveSettings()
                }
                default: SettingsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                tabButton(0, "对话", "bubble.left.and.bubble.right")
                tabButton(1, "写作", "text.alignleft")
                tabButton(2, "会话", "folder")
                tabButton(3, "资料", "square.grid.2x2")
                tabButton(4, "设置", "slider.horizontal.3")
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Theme.surface)
        }
    }

    private func tabButton(_ index: Int, _ title: String, _ icon: String) -> some View {
        Button {
            tab = index
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                Text(title).font(.system(size: 10.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(tab == index ? Theme.accent : Theme.faint)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 应用状态

@MainActor
public final class AppModel: ObservableObject {

    @Published public var sessions: [Session] = []
    @Published public var currentIndex: Int = 0
    @Published public var settings: AppSettings = AppSettings()
    @Published public var licenseActive = false
    @Published public var licenseMessage = ""
    @Published public var isStreaming = false
    @Published public var errorText: String?
    @Published public var deviceId = ""
    @Published public var apiKeyMasked = "未配置"

    private let store = Store.shared
    private var task: Task<Void, Never>?

    public init() {}

    public var current: Session {
        if sessions.isEmpty { sessions = [Session()] }
        return sessions[min(currentIndex, sessions.count - 1)]
    }

    public func bootstrap() {
        sessions = store.loadSessions()
        if sessions.isEmpty { sessions = [Session()] }
        settings = store.loadSettings()
        settings = ProviderStore.shared.settingsApplyingCurrent(settings)
        deviceId = store.deviceId()
        apiKeyMasked = store.maskedAPIKey()
        refreshLicense()
    }

    public func refreshLicense() {
        guard let envelope = store.loadLicenseEnvelope() else {
            licenseActive = false
            return
        }
        switch LicenseVerifier.evaluate(envelope, currentDevice: deviceId) {
        case .active:
            licenseActive = true
            licenseMessage = ""
        case let .expired(claims):
            licenseActive = false
            licenseMessage = "凭证已于 \(dateString(claims.expiresAt)) 过期"
        case let .wrongDevice(bound):
            licenseActive = false
            licenseMessage = "该凭证绑定的是另一台设备（\(bound)）"
        case let .invalid(reason):
            licenseActive = false
            licenseMessage = reason
        case .inactive:
            licenseActive = false
        }
    }

    public func activate(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            licenseMessage = "先粘贴兑换码"
            return
        }
        switch LicenseVerifier.evaluate(trimmed, currentDevice: deviceId) {
        case .active:
            store.saveLicenseEnvelope(trimmed)
            licenseActive = true
            licenseMessage = "兑换成功，已激活"
        case let .expired(claims):
            licenseMessage = "该凭证已于 \(dateString(claims.expiresAt)) 过期"
        case let .wrongDevice(bound):
            licenseMessage = "该凭证绑定的是另一台设备（\(bound)），请联系作者按本机设备号重新签发"
        case let .invalid(reason):
            licenseMessage = reason
        case .inactive:
            licenseMessage = "无法识别这枚凭证"
        }
    }

    public func deactivate() {
        store.clearLicense()
        licenseActive = false
        licenseMessage = "已重置为未激活"
    }

    // MARK: 会话

    public func newSession() {
        sessions.insert(Session(mode: settings.defaultMode), at: 0)
        currentIndex = 0
        persist()
    }

    public func delete(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        if sessions.isEmpty { sessions = [Session()] }
        currentIndex = min(currentIndex, sessions.count - 1)
        persist()
    }

    public func persist() { store.saveSessions(sessions) }

    /// 酒馆页交过来的一次性设定块。发一条就清掉，避免下一轮还在起效。
    @Published public var pendingSystem: String = ""

    /// 酒馆页发起剧情：先记设定，再走普通发送。
    public func beginTavern(system: String, user: String) {
        pendingSystem = system
        send(user)
    }

    public func send(_ text: String, attachments: [Attachment] = []) {
        guard licenseActive else {
            errorText = "授权未通过，请先兑换"
            return
        }
        let apiKey = store.apiKey() ?? ""
        guard !apiKey.isEmpty else {
            errorText = ApiClient.ApiError.noKey.localizedDescription
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var session = current
        session.messages.append(Message(role: .user, text: trimmed, attachments: attachments))
        session.retitleFromFirstMessage()
        session.messages.append(Message(role: .assistant, text: ""))
        sessions[currentIndex] = session

        let history = Array(session.messages.dropLast())
        let mode = session.mode
        isStreaming = true
        errorText = nil

        task = Task { [weak self] in
            guard let self else { return }
            let client = ApiClient(settings: self.settings, apiKey: apiKey)
            // 三层设定按「模式默认 → 角色卡 → 记忆」叠加，酒馆块放最前（它最具体）。
            var system = PersonaStore().systemPrompt(basedOn: Prompts.system(for: mode))
            system = MemoryStore().systemPrompt(basedOn: system)
            if !self.pendingSystem.isEmpty {
                system = self.pendingSystem + "\n\n" + system
            }
            client.systemOverride = system.isEmpty ? nil : system
            do {
                let reply = try await client.stream(messages: history, mode: mode) { piece in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        var s = self.current
                        guard let last = s.messages.last, last.role == .assistant else { return }
                        s.messages[s.messages.count - 1].text += piece
                        self.sessions[self.currentIndex] = s
                    }
                }
                await MainActor.run {
                    UsageStore.shared.record(
                        sessionId: session.id,
                        model: self.settings.provider.model,
                        providerName: self.settings.provider.name,
                        history: history,
                        reply: reply
                    )
                    self.pendingSystem = ""
                    self.isStreaming = false
                    self.persist()
                }
            } catch {
                await MainActor.run {
                    self.errorText = error.localizedDescription
                    self.isStreaming = false
                    var s = self.current
                    if let last = s.messages.last, last.role == .assistant, last.text.isEmpty {
                        s.messages.removeLast()
                        self.sessions[self.currentIndex] = s
                    }
                    self.persist()
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
        isStreaming = false
    }

    public func regenerate() {
        var s = current
        if s.messages.last?.role == .assistant { s.messages.removeLast() }
        sessions[currentIndex] = s
        let history = s.messages
        guard let lastUser = history.last(where: { $0.role == .user }) else { return }
        send(lastUser.text)
    }

    // MARK: 校对

    public func testConnection() async -> String {
        let key = store.apiKey() ?? ""
        guard !key.isEmpty else { return "先填 API Key" }
        let client = ApiClient(settings: settings, apiKey: key)
        do {
            let models = try await client.listModels()
            return models.isEmpty ? "连通正常（没返回模型列表）" : "连通正常，可用模型 \(models.count) 个：\(models.prefix(3).joined(separator: "、"))"
        } catch {
            return error.localizedDescription
        }
    }

    public func saveSettings() {
        store.saveSettings(settings)
        apiKeyMasked = store.maskedAPIKey()
    }

    public func setAPIKey(_ key: String) {
        store.setAPIKey(key)
        apiKeyMasked = store.maskedAPIKey()
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}