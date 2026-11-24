import Foundation
import Security

/// 本地存储：会话与设置在应用沙盒的 JSON 文件里；设备号与 API Key 进 Keychain。
public final class Store {

    public static let shared = Store()

    private let queue = DispatchQueue(label: "deepchat.store")
    private let folder: URL
    private let keychainService = "com.yanchuan.writer.ios"

    public init(folder: URL? = nil) {
        if let folder {
            self.folder = folder
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.folder = base.appendingPathComponent("DeepChat", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        protect(self.folder)
    }

    // MARK: - 文件保护

    /// 锁屏后这些 JSON 读不到：iOS 数据保护 `complete`。macOS 上没有这个 API（会抛错），
    /// 所以整段用 `#if os(iOS)` 圈起来，host 侧 `swift build` 不受影响。
    private func protect(_ url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        #endif
    }

    // MARK: - 会话

    private var sessionsURL: URL { folder.appendingPathComponent("sessions.json") }

    public func loadSessions() -> [Session] {
        guard let data = try? Data(contentsOf: sessionsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Session].self, from: data)) ?? []
    }

    public func saveSessions(_ sessions: [Session]) {
        queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(sessions) else { return }
            try? data.write(to: sessionsURL, options: .atomic)
            protect(sessionsURL)
        }
    }

    // MARK: - 设置

    private var settingsURL: URL { folder.appendingPathComponent("settings.json") }

    public func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else { return AppSettings() }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    public func saveSettings(_ settings: AppSettings) {
        queue.sync {
            guard let data = try? JSONEncoder().encode(settings) else { return }
            try? data.write(to: settingsURL, options: .atomic)
            protect(settingsURL)
        }
    }

    // MARK: - 授权

    private var licenseURL: URL { folder.appendingPathComponent("license.json") }

    public struct StoredLicense: Codable {
        public var envelope: String
        public var savedAt: Date
    }

    public func loadLicenseEnvelope() -> String? {
        guard let data = try? Data(contentsOf: licenseURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(StoredLicense.self, from: data))?.envelope
    }

    public func saveLicenseEnvelope(_ envelope: String) {
        queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(StoredLicense(envelope: envelope, savedAt: Date())) else { return }
            try? data.write(to: licenseURL, options: .atomic)
            protect(licenseURL)
        }
    }

    public func clearLicense() {
        try? FileManager.default.removeItem(at: licenseURL)
    }

    // MARK: - 设备号

    /// 存在 Keychain：卸载重装仍在，换机才变化。作者按它签发离线凭证。
    public func deviceId() -> String {
        let account = "device-id"
        if let existing = keychainRead(account: account) { return existing }
        let fresh = LicenseVerifier.makeDeviceId()
        keychainWrite(account: account, value: fresh)
        return fresh
    }

    // MARK: - API Key（Keychain）

    public func apiKey() -> String? {
        keychainRead(account: "api-key")
    }

    public func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keychainDelete(account: "api-key")
        } else {
            keychainWrite(account: "api-key", value: trimmed)
        }
    }

    public func maskedAPIKey() -> String {
        guard let key = apiKey(), !key.isEmpty else { return "未配置" }
        if key.count <= 8 { return String(repeating: "•", count: key.count) }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }

    // MARK: - Keychain 原语

    private func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
    }

    private func keychainRead(account: String) -> String? {
        var q = keychainQuery(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainWrite(account: String, value: String) {
        let data = Data(value.utf8)
        let q = keychainQuery(account: account)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private func keychainDelete(account: String) {
        SecItemDelete(keychainQuery(account: account) as CFDictionary)
    }
}