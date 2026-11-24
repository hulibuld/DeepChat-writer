import SwiftUI
import Security
import DeepChatCore

// MARK: - API Key（Keychain）

/// 每个通道一个 Keychain 账号：`provider-key-<uuid>`，与 `Store` 用同一个 service，
/// 界面只显示掩码。`Store` 的全局 Key 按 `api-key` 单独存放，两条互不覆盖。
public enum ProviderKeychain {

    private static let service = "com.yanchuan.writer.ios"

    public static func account(_ id: UUID) -> String { "provider-key-\(id.uuidString)" }

    public static func key(for id: UUID) -> String? {
        var query = baseQuery(account: account(id))
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func setKey(_ value: String, for id: UUID) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            removeKey(for: id)
            return
        }
        let data = Data(trimmed.utf8)
        let query = baseQuery(account: account(id))
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func removeKey(for id: UUID) {
        SecItemDelete(baseQuery(account: account(id)) as CFDictionary)
    }

    public static func hasKey(for id: UUID) -> Bool {
        guard let key = key(for: id) else { return false }
        return !key.isEmpty
    }

    /// 掩码：不足 8 位全打码，其余保留首尾各 4 位。
    public static func masked(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "未配置" }
        if key.count <= 8 { return String(repeating: "•", count: key.count) }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

// MARK: - 通道存储

/// 多通道管理：列表与「当前通道」存 `providers.json`，Key 在 Keychain。
/// 独立于 `AppModel`；选中当前通道后用 `settingsApplyingCurrent(_:)` 交给调用方写回设置。
public final class ProviderStore: ObservableObject {

    public static let shared = ProviderStore()

    @Published public private(set) var providers: [Provider] = []
    @Published public private(set) var currentID: UUID?

    private let folder: URL
    private let ioQueue = DispatchQueue(label: "deepchat.providers")

    private struct Snapshot: Codable {
        var currentID: UUID?
        var providers: [Provider]
    }

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

    private var fileURL: URL { folder.appendingPathComponent("providers.json") }

    // MARK: 读

    public var current: Provider? {
        guard let currentID else { return providers.first }
        return providers.first { $0.id == currentID } ?? providers.first
    }

    public func reload() {
        load()
    }

    private func load() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? decoder.decode(Snapshot.self, from: data),
           !snapshot.providers.isEmpty {
            providers = snapshot.providers
            currentID = snapshot.currentID ?? snapshot.providers.first?.id
            return
        }
        let seed = Provider()
        providers = [seed]
        currentID = seed.id
        save()
    }

    // MARK: 写

    public func select(_ id: UUID) {
        guard providers.contains(where: { $0.id == id }) else { return }
        currentID = id
        save()
    }

    @discardableResult
    public func add(name: String, baseURL: String, model: String,
                    kind: ProviderKind = .openaiCompatible) -> Provider {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = Provider(
            name: trimmedName.isEmpty ? "新通道" : trimmedName,
            baseURL: trimmedURL,
            kind: kind,
            model: trimmedModel.isEmpty ? "deepseek-chat" : trimmedModel
        )
        providers.append(provider)
        save()
        return provider
    }

    public func update(_ provider: Provider) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[index] = provider
        save()
    }

    /// 删除通道；只剩一个时不动，删的是当前通道就自动切到剩下的第一个。
    /// 顺带清掉它的 Keychain 条目。
    public func remove(_ id: UUID) {
        guard providers.count > 1 else { return }
        providers.removeAll { $0.id == id }
        ProviderKeychain.removeKey(for: id)
        if currentID == id {
            currentID = providers.first?.id
        }
        save()
    }

    /// 把「当前通道」写进既有设置，调用方拿到后调用 `model.saveSettings()`。
    public func settingsApplyingCurrent(_ settings: AppSettings) -> AppSettings {
        var next = settings
        if let current { next.provider = current }
        return next
    }

    /// 首次升级时把「设置」里的全局 Key 复制给某个通道。
    @discardableResult
    public func adoptLegacyKey(for id: UUID) -> Bool {
        guard let legacy = Store.shared.apiKey(), !legacy.isEmpty else { return false }
        ProviderKeychain.setKey(legacy, for: id)
        return true
    }

    private func save() {
        let snapshot = Snapshot(currentID: currentID, providers: providers)
        let url = fileURL
        ioQueue.sync {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - 界面

/// 通道管理页：增删改、设为当前、Key 存 Keychain。
/// `onSelect` 是把选中通道写回 `AppModel.settings` 的胶水点：
/// ```swift
/// ProvidersView { provider in
///     model.settings.provider = provider
///     model.saveSettings()
/// }
/// ```
public struct ProvidersView: View {

    @StateObject private var store: ProviderStore
    private let onSelect: ((Provider) -> Void)?
    @State private var adding = false

    public init(store: ProviderStore? = nil, onSelect: ((Provider) -> Void)? = nil) {
        _store = StateObject(wrappedValue: store ?? ProviderStore.shared)
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    if store.providers.isEmpty {
                        Text("还没有通道，先新建一个。")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(store.providers) { provider in
                        ProviderCard(
                            provider: provider,
                            isCurrent: provider.id == (store.current?.id ?? provider.id),
                            onSave: { store.update($0) },
                            onSelect: {
                                store.select(provider.id)
                                onSelect?(provider)
                            },
                            onDelete: { store.remove(provider.id) },
                            onAdoptLegacyKey: { store.adoptLegacyKey(for: provider.id) },
                            canDelete: store.providers.count > 1 && provider.id != store.current?.id
                        )
                        .id(provider.id)
                    }
                    hint
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $adding) {
            ProviderAddSheet { name, url, model, kind in
                store.add(name: name, baseURL: url, model: model, kind: kind)
                adding = false
            } onCancel: {
                adding = false
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("通道")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                adding = true
            } label: {
                Text("新建")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }

    private var hint: some View {
        Text("Key 存在系统 Keychain，每个通道一个；界面只显示首尾各 4 位。切换「当前」后，新请求走这个通道的地址与模型。")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 单个通道卡片

private struct ProviderCard: View {

    let provider: Provider
    let isCurrent: Bool
    let onSave: (Provider) -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onAdoptLegacyKey: () -> Bool
    let canDelete: Bool

    @State private var name: String
    @State private var baseURL: String
    @State private var model: String
    @State private var kind: ProviderKind
    @State private var keyInput = ""
    @State private var keyMask: String

    init(provider: Provider, isCurrent: Bool,
         onSave: @escaping (Provider) -> Void, onSelect: @escaping () -> Void,
         onDelete: @escaping () -> Void, onAdoptLegacyKey: @escaping () -> Bool,
         canDelete: Bool) {
        self.provider = provider
        self.isCurrent = isCurrent
        self.onSave = onSave
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onAdoptLegacyKey = onAdoptLegacyKey
        self.canDelete = canDelete
        _name = State(initialValue: provider.name)
        _baseURL = State(initialValue: provider.baseURL)
        _model = State(initialValue: provider.model)
        _kind = State(initialValue: provider.kind)
        _keyMask = State(initialValue: ProviderKeychain.masked(ProviderKeychain.key(for: provider.id)))
    }

    private var legacyKeyAvailable: Bool {
        guard let legacy = Store.shared.apiKey() else { return false }
        return !legacy.isEmpty && !ProviderKeychain.hasKey(for: provider.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(name.isEmpty ? provider.name : name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if isCurrent {
                    Text("当前")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.18))
                        .foregroundStyle(Theme.accent)
                        .clipShape(Capsule())
                }
                Spacer(minLength: 8)
                if !isCurrent {
                    Button("设为当前", action: onSelect)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                }
            }

            field("显示名", text: $name)
            field("Base URL", text: $baseURL)
            field("模型", text: $model)

            HStack(spacing: 6) {
                ForEach(kindOptions, id: \.self) { option in
                    Button {
                        kind = option
                    } label: {
                        Text(kindLabel(option))
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(kind == option ? Theme.accent : Theme.surface2)
                            .foregroundStyle(kind == option ? Theme.accentInk : Theme.dim)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("保存") { commit() }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
            }

            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("API Key")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faint)
                    Spacer()
                    Text(keyMask)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                }
                HStack(spacing: 8) {
                    SecureField("粘贴 Key", text: $keyInput)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .padding(9)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Button("存") { saveKey() }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                    if ProviderKeychain.hasKey(for: provider.id) {
                        Button("清除") { clearKey() }
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.danger)
                            .buttonStyle(.plain)
                    }
                }
                if legacyKeyAvailable {
                    Button("沿用「设置」里的 Key") {
                        if onAdoptLegacyKey() {
                            keyMask = ProviderKeychain.masked(ProviderKeychain.key(for: provider.id))
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.dim)
                    .buttonStyle(.plain)
                }
            }

            if canDelete {
                Button("删除这个通道", action: onDelete)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .buttonStyle(.plain)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .onChange(of: provider) { fresh in
            name = fresh.name
            baseURL = fresh.baseURL
            model = fresh.model
            kind = fresh.kind
            keyMask = ProviderKeychain.masked(ProviderKeychain.key(for: fresh.id))
        }
    }

    private var kindOptions: [ProviderKind] { [.deepSeek, .openaiCompatible] }

    private func kindLabel(_ kind: ProviderKind) -> String {
        switch kind {
        case .deepSeek: return "DeepSeek"
        case .openaiCompatible: return "OpenAI 兼容"
        }
    }

    private func commit() {
        var next = provider
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.name = trimmedName.isEmpty ? provider.name : trimmedName
        next.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        next.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        next.kind = kind
        onSave(next)
        name = next.name
    }

    private func saveKey() {
        ProviderKeychain.setKey(keyInput, for: provider.id)
        keyInput = ""
        keyMask = ProviderKeychain.masked(ProviderKeychain.key(for: provider.id))
    }

    private func clearKey() {
        ProviderKeychain.removeKey(for: provider.id)
        keyMask = ProviderKeychain.masked(nil)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.faint)
            TextField("", text: text)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.ink)
                .autocorrectionDisabled()
                .padding(9)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

// MARK: - 新建通道

private struct ProviderAddSheet: View {

    let onCreate: (String, String, String, ProviderKind) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var baseURL = "https://api.deepseek.com"
    @State private var model = "deepseek-chat"
    @State private var kind: ProviderKind = .deepSeek

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建通道")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)

            labeled("显示名") {
                TextField("例如 硅基流动", text: $name)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Theme.surface2)
                    .foregroundStyle(Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            labeled("Base URL") {
                TextField("https://api.deepseek.com", text: $baseURL)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Theme.surface2)
                    .foregroundStyle(Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            labeled("模型") {
                TextField("deepseek-chat", text: $model)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Theme.surface2)
                    .foregroundStyle(Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            labeled("类型") {
                HStack(spacing: 8) {
                    ForEach([ProviderKind.deepSeek, .openaiCompatible], id: \.self) { option in
                        Button {
                            kind = option
                            if option == .openaiCompatible && model == "deepseek-chat" {
                                model = ""
                            }
                        } label: {
                            Text(option == .deepSeek ? "DeepSeek" : "OpenAI 兼容")
                                .font(.system(size: 12.5, weight: .medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(kind == option ? Theme.accent : Theme.surface2)
                                .foregroundStyle(kind == option ? Theme.accentInk : Theme.dim)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                GhostButton("取消", action: onCancel)
                PrimaryButton("创建") {
                    onCreate(name, baseURL, model, kind)
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg)
    }

    private func labeled<Content: View>(_ label: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.faint)
            content()
        }
    }
}