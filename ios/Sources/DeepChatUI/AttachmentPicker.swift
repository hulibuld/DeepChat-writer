import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import DeepChatCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 待发附件草稿

/// 输入行上方的附件草稿：选中的东西先落到 `attachments/`，发送时把清单拼进正文。
/// 与 `AppModel` 无关，视图自己 `@StateObject` 一只。
public final class AttachmentDraft: ObservableObject {

    @Published public private(set) var items: [Attachment] = []
    @Published public private(set) var errorText = ""

    public init() {}

    public var isEmpty: Bool { items.isEmpty }

    /// 发送时拼到正文末尾的那段（附件不进请求体，只是本地存档的清单）。
    public var messageSuffix: String { Attachments.messageSuffix(items) }

    public func addImage(data: Data, name: String? = nil) {
        do {
            items.append(try Attachments.shared.saveImage(data: data, fileName: name))
            errorText = ""
        } catch {
            errorText = error.localizedDescription
        }
    }

    public func addFile(url: URL) {
        do {
            items.append(try Attachments.shared.saveFile(url: url))
            errorText = ""
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// 外部（例如 fileImporter 整体失败）传一句话进来。
    public func note(_ message: String) {
        errorText = message
    }

    public func remove(_ id: UUID) {
        Attachments.shared.remove(id: id)
        items.removeAll { $0.id == id }
        if items.isEmpty { errorText = "" }
    }

    /// 清草稿：把已经落盘的也删掉，不留垃圾。
    public func clear() {
        for item in items { Attachments.shared.remove(item) }
        items = []
        errorText = ""
    }
}

// MARK: - 缩略图条

/// 一条横向的附件预览：图片给缩略图，文件给图标 + 名字。
/// `onRemove` 传 nil 就是只读展示（用于已发送的历史消息）。
public struct AttachmentStrip: View {

    public let attachments: [Attachment]
    public let onRemove: ((UUID) -> Void)?

    public init(attachments: [Attachment], onRemove: ((UUID) -> Void)? = nil) {
        self.attachments = attachments
        self.onRemove = onRemove
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { item in
                    chip(item)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ item: Attachment) -> some View {
        HStack(spacing: 7) {
            if item.kind == .image, let image = thumbnail(item) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: item.kind == .image ? "photo" : "doc")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.fileName)
                    .font(.system(size: Theme.size(12), weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 130, alignment: .leading)
                Text(item.displaySize)
                    .font(.system(size: Theme.size(10.5)))
                    .foregroundStyle(Theme.faint)
            }

            if let onRemove {
                Button {
                    onRemove(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func thumbnail(_ item: Attachment) -> Image? {
        let url = Attachments.shared.url(for: item)
        #if canImport(UIKit)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}

// MARK: - 选择器

/// 输入行上方的一排按钮 + 附件预览条。图片走 `PhotosPicker`，文件走 `fileImporter`，
/// 都不需要额外权限声明（系统面板自己收口）。
public struct AttachmentPicker: View {

    @ObservedObject var draft: AttachmentDraft

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pickingFile = false
    @State private var loading = false

    public init(draft: AttachmentDraft) {
        self.draft = draft
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItems,
                             maxSelectionCount: 5,
                             matching: .images,
                             photoLibrary: .shared()) {
                    label("photo", "图片")
                }
                .buttonStyle(.plain)

                Button {
                    pickingFile = true
                } label: {
                    label("folder", "文件")
                }
                .buttonStyle(.plain)

                if loading {
                    ProgressView().tint(Theme.dim).scaleEffect(0.7)
                }

                Spacer()

                if !draft.items.isEmpty {
                    Button {
                        draft.clear()
                    } label: {
                        Text("清空")
                            .font(.system(size: Theme.size(11.5)))
                            .foregroundStyle(Theme.faint)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !draft.errorText.isEmpty {
                Text(draft.errorText)
                    .font(.system(size: Theme.size(11.5)))
                    .foregroundStyle(Theme.danger)
                    .lineLimit(2)
            }

            if !draft.items.isEmpty {
                AttachmentStrip(attachments: draft.items) { id in
                    draft.remove(id)
                }
            }
        }
        .fileImporter(isPresented: $pickingFile,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            switch result {
            case let .success(urls):
                for url in urls { draft.addFile(url: url) }
            case let .failure(error):
                draft.note("选文件失败：\(error.localizedDescription)")
            }
        }
        .onChange(of: photoItems) { picked in
            guard !picked.isEmpty else { return }
            load(picked)
        }
    }

    private func load(_ picked: [PhotosPickerItem]) {
        loading = true
        Task {
            for item in picked {
                if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                    await MainActor.run { draft.addImage(data: data) }
                } else {
                    await MainActor.run { draft.note("有一张图片读不出来，已跳过") }
                }
            }
            await MainActor.run {
                loading = false
                photoItems = []
            }
        }
    }

    private func label(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text(title)
                .font(.system(size: Theme.size(12)))
        }
        .foregroundStyle(Theme.dim)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface2)
        .clipShape(Capsule())
    }
}