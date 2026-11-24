import Foundation

// MARK: - 附件模型

public enum AttachmentKind: String, Codable, Sendable {
    case image
    case file
}

/// 一条本地附件。文件本体存在 `Application Support/DeepChat/attachments/`，
/// `relativePath` 相对 DeepChat 根目录（形如 `attachments/<uuid>.png`）。
public struct Attachment: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var kind: AttachmentKind
    public var fileName: String
    public var relativePath: String
    public var byteSize: Int
    public var createdAt: Date

    public init(id: UUID = UUID(), kind: AttachmentKind, fileName: String,
                relativePath: String, byteSize: Int, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.relativePath = relativePath
        self.byteSize = max(0, byteSize)
        self.createdAt = createdAt
    }

    public var displaySize: String { Attachments.sizeText(byteSize) }
}

// MARK: - 附件错误

public enum AttachmentError: LocalizedError, Equatable {
    case tooLarge(name: String, bytes: Int)
    case unreadable(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .tooLarge(name, bytes):
            return "「\(name)」有 \(Attachments.sizeText(bytes))，超过单个附件 20 MB 的上限"
        case let .unreadable(name):
            return "读不了「\(name)」，文件可能已被移动或没有访问权限"
        case let .writeFailed(name):
            return "保存「\(name)」失败，请检查本机存储空间"
        }
    }
}

// MARK: - 附件存储

/// 附件落盘：`Application Support/DeepChat/attachments/`。
/// 只做本地存档，不参与请求体；macOS 上仍可编译（文件保护那段用 `#if os(iOS)` 圈起来）。
public final class Attachments {

    public static let shared = Attachments()

    /// 单文件上限 20 MB，和 Android 端口径一致。
    public static let maxBytes = 20 * 1024 * 1024

    private let folder: URL

    public init(folder: URL? = nil) {
        if let folder {
            self.folder = folder
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.folder = base.appendingPathComponent("DeepChat", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        protect(directory)
    }

    public var directory: URL { folder.appendingPathComponent("attachments", isDirectory: true) }

    // MARK: 写入

    /// 存一张图片。扩展名按文件头猜，`fileName` 为空时按时间命名。
    public func saveImage(data: Data, fileName: String? = nil) throws -> Attachment {
        guard data.count <= Attachments.maxBytes else {
            throw AttachmentError.tooLarge(name: fileName ?? "图片", bytes: data.count)
        }
        let ext = Attachments.imageExtension(for: data)
        let raw = fileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = raw.isEmpty ? "图片-\(Attachments.stamp())" : raw
        let safe = Attachments.sanitize(base, fallbackExtension: ext)
        let id = UUID()
        let attachment = Attachment(
            id: id,
            kind: .image,
            fileName: safe,
            relativePath: relativePath(for: id, fileName: safe),
            byteSize: data.count
        )
        try write(data, to: url(for: attachment), displayName: safe)
        return attachment
    }

    /// 存一个文件（拷一份到沙盒，原文件之后可以删）。
    public func saveFile(url source: URL) throws -> Attachment {
        let name = source.lastPathComponent.isEmpty ? "附件" : source.lastPathComponent
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let values = try? source.resourceValues(forKeys: [.fileSizeKey])
        let size = values?.fileSize ?? 0
        guard size <= Attachments.maxBytes else {
            throw AttachmentError.tooLarge(name: name, bytes: size)
        }
        let ext = Attachments.fileExtension(for: name)
        let safe = Attachments.sanitize(name, fallbackExtension: ext)
        guard let data = try? Data(contentsOf: source) else {
            throw AttachmentError.unreadable(name)
        }
        guard data.count <= Attachments.maxBytes else {
            throw AttachmentError.tooLarge(name: name, bytes: data.count)
        }
        let id = UUID()
        let attachment = Attachment(
            id: id,
            kind: .file,
            fileName: safe,
            relativePath: relativePath(for: id, fileName: safe),
            byteSize: data.count
        )
        try write(data, to: url(for: attachment), displayName: safe)
        return attachment
    }

    /// 直接落一段文本（导入的 JSON、导出的 Markdown 之类）。
    public func saveText(_ text: String, fileName: String) throws -> Attachment {
        let data = Data(text.utf8)
        guard data.count <= Attachments.maxBytes else {
            throw AttachmentError.tooLarge(name: fileName, bytes: data.count)
        }
        let safe = Attachments.sanitize(fileName, fallbackExtension: "txt")
        let id = UUID()
        let attachment = Attachment(
            id: id,
            kind: .file,
            fileName: safe,
            relativePath: relativePath(for: id, fileName: safe),
            byteSize: data.count
        )
        try write(data, to: url(for: attachment), displayName: safe)
        return attachment
    }

    // MARK: 读取 / 删除

    /// 附件在本机的绝对地址（不保证文件还在）。
    public func url(for attachment: Attachment) -> URL {
        folder.appendingPathComponent(attachment.relativePath)
    }

    public func exists(_ attachment: Attachment) -> Bool {
        FileManager.default.fileExists(atPath: url(for: attachment).path)
    }

    /// 按 id 删：文件名以 `<uuid>.` 开头，扫一遍目录即可，不依赖调用方记得路径。
    public func remove(id: UUID) {
        let manager = FileManager.default
        let prefix = id.uuidString.lowercased() + "."
        let list = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in list where file.lastPathComponent.lowercased().hasPrefix(prefix) {
            try? manager.removeItem(at: file)
        }
    }

    public func remove(_ attachment: Attachment) {
        try? FileManager.default.removeItem(at: url(for: attachment))
    }

    // MARK: 拼进消息

    /// 附件不进请求体，只在正文末尾留一份可回溯的清单。
    public static func messageSuffix(_ attachments: [Attachment]) -> String {
        guard !attachments.isEmpty else { return "" }
        var lines = "\n\n[附件]"
        for item in attachments {
            let kind = item.kind == .image ? "图片" : "文件"
            lines += "\n- \(kind)：\(item.fileName)（\(item.displaySize)）"
        }
        return lines + "\n"
    }

    // MARK: 名字与大小

    /// 去掉路径分隔符、`..`、控制字符，压掉连续空白，保留扩展名，最多 64 字符。
    public static func sanitize(_ name: String, fallbackExtension: String = "bin") -> String {
        var cleaned = name
            .replacingOccurrences(of: "\\", with: "/")
            .components(separatedBy: "/")
            .last ?? name
        cleaned = cleaned.replacingOccurrences(of: "..", with: "-")
        cleaned = cleaned.components(separatedBy: CharacterSet.controlCharacters).joined()
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { cleaned = "附件" }

        let ext = fileExtension(for: cleaned)
        let stem = ext.isEmpty ? cleaned : String(cleaned.dropLast(ext.count + 1))
        let safeStem = stem.isEmpty ? "附件" : String(stem.prefix(48))
        let safeExt = ext.isEmpty ? fallbackExtension : ext
        return "\(safeStem).\(safeExt)"
    }

    public static func sizeText(_ bytes: Int) -> String {
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        }
        if bytes >= 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        }
        return "\(bytes) B"
    }

    // MARK: 内部

    private func relativePath(for id: UUID, fileName: String) -> String {
        // 磁盘文件用附件自己的 uuid 打头：同目录不撞名，remove(id:) 按前缀就能找到。
        let stem = id.uuidString.lowercased()
        let ext = Attachments.fileExtension(for: fileName)
        let stored = ext.isEmpty ? stem : "\(stem).\(ext)"
        return "attachments/\(stored)"
    }

    private func write(_ data: Data, to target: URL, displayName: String) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            throw AttachmentError.writeFailed(displayName)
        }
        protect(target)
        protect(directory)
    }

    /// 锁屏后附件读不到（iOS 数据保护 complete）。macOS 上没有这个 API，直接跳过。
    private func protect(_ url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        #endif
    }

    private static func fileExtension(for name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot < name.index(before: name.endIndex) else { return "" }
        let ext = String(name[name.index(after: dot)...]).lowercased()
        guard ext.count <= 8,
              ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { return "" }
        return ext
    }

    private static func imageExtension(for data: Data) -> String {
        let head = [UInt8](data.prefix(12))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if head.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if head.starts(with: [0x52, 0x49, 0x46, 0x46]) && head.count >= 12 { return "webp" }
        if head.starts(with: [0x00, 0x00, 0x00]) { return "heic" }
        return "img"
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}