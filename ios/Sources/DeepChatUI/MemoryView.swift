import SwiftUI
import DeepChatCore

/// 记忆库：一组可开关的条目，启用中的条目拼进系统提示词。
/// 本视图自带 `@StateObject`，不依赖 `AppModel`。
public struct MemoryView: View {

    private enum Filter: String, CaseIterable {
        case all, active

        var label: String { self == .all ? "全部" : "已启用" }
    }

    @StateObject private var store = MemoryStore()
    @State private var editing: MemoryItem?
    @State private var filter: Filter = .all
    @State private var promptVisible = false

    public init() {}

    private var visibleItems: [MemoryItem] {
        let list = store.items.sorted { $0.createdAt < $1.createdAt }
        return filter == .all ? list : list.filter(\.enabled)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 18) {
                ForEach(Filter.allCases, id: \.self) { item in
                    Button {
                        filter = item
                    } label: {
                        Text(item.label)
                            .font(.system(size: Theme.size(13.5), weight: filter == item ? .semibold : .regular))
                            .foregroundStyle(filter == item ? Theme.ink : Theme.faint)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(store.activeLines().count) / \(store.items.count) 条启用")
                    .font(.system(size: Theme.size(11.5)))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if visibleItems.isEmpty {
                        Text(store.items.isEmpty
                             ? "还没有记忆。点右上角「添加」写一条，例如「主角性格：沉默，不爱解释」。"
                             : "没有启用中的条目。")
                            .font(.system(size: Theme.size(12.5)))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 8)
                    }

                    ForEach(visibleItems) { item in
                        row(item)
                    }

                    promptBlock
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
        .sheet(item: $editing) { item in
            MemoryEditorView(
                item: item,
                isNew: store.item(id: item.id) == nil,
                onSave: { saved in
                    if store.item(id: saved.id) == nil {
                        store.add(saved)
                    } else {
                        store.update(saved)
                    }
                    editing = nil
                },
                onDelete: { doomed in
                    store.delete(id: doomed.id)
                    editing = nil
                }
            )
        }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack {
            Text("记忆")
                .font(.system(size: Theme.size(20), weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                editing = MemoryItem()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("添加")
                        .font(.system(size: Theme.size(14), weight: .medium))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }

    // MARK: 条目

    private func row(_ item: MemoryItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title.isEmpty ? "未命名" : item.title)
                        .font(.system(size: Theme.size(14.5), weight: .medium))
                        .foregroundStyle(item.enabled ? Theme.ink : Theme.dim)
                        .lineLimit(1)
                    Text(item.kind.label)
                        .font(.system(size: Theme.size(10)))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                if !item.content.isEmpty {
                    Text(item.content)
                        .font(.system(size: Theme.size(12.5)))
                        .foregroundStyle(item.enabled ? Theme.dim : Theme.faint)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editing = item }

            Toggle("", isOn: Binding(
                get: { item.enabled },
                set: { store.setEnabled($0, id: item.id) }
            ))
            .labelsHidden()
            .tint(Theme.accent)
        }
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(item.enabled ? 1 : 0.75)
    }

    // MARK: 提示词预览

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("拼进提示词的记忆")
                    .font(.system(size: Theme.size(12), weight: .semibold))
                    .foregroundStyle(Theme.faint)
                Spacer()
                Button(promptVisible ? "收起" : "预览") {
                    promptVisible.toggle()
                }
                .font(.system(size: Theme.size(12.5), weight: .medium))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }

            if promptVisible {
                let block = store.promptBlock()
                Text(block.isEmpty ? "没有启用的条目，系统提示词不会被追加内容。" : block)
                    .font(.system(size: Theme.size(11.5), design: .monospaced))
                    .foregroundStyle(Theme.dim)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - 编辑器

private struct MemoryEditorView: View {

    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    let onSave: (MemoryItem) -> Void
    let onDelete: (MemoryItem) -> Void

    @State private var draft: MemoryItem

    init(item: MemoryItem,
         isNew: Bool,
         onSave: @escaping (MemoryItem) -> Void,
         onDelete: @escaping (MemoryItem) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: item)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                    .font(.system(size: Theme.size(14)))
                    .foregroundStyle(Theme.dim)
                    .buttonStyle(.plain)
                Spacer()
                Text(isNew ? "新建记忆" : "编辑记忆")
                    .font(.system(size: Theme.size(15), weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("保存") {
                    draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !draft.isBlank else { return }
                    onSave(draft)
                    dismiss()
                }
                .font(.system(size: Theme.size(14), weight: .semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("标题 / 键")
                            .font(.system(size: Theme.size(11.5)))
                            .foregroundStyle(Theme.faint)
                        TextField("例如：主角性格", text: $draft.title)
                            .font(.system(size: Theme.size(14)))
                            .foregroundStyle(Theme.ink)
                            .padding(10)
                            .background(Theme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("内容")
                            .font(.system(size: Theme.size(11.5)))
                            .foregroundStyle(Theme.faint)
                        ZStack(alignment: .topLeading) {
                            if draft.content.isEmpty {
                                Text("一句话或一小段，例如：沉默寡言，遇事先看窗外")
                                    .font(.system(size: Theme.size(13)))
                                    .foregroundStyle(Theme.faint)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $draft.content)
                                .font(.system(size: Theme.size(14)))
                                .foregroundColor(Theme.ink)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .frame(minHeight: 120)
                        }
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("类型")
                            .font(.system(size: Theme.size(11.5)))
                            .foregroundStyle(Theme.faint)
                        Picker("", selection: $draft.kind) {
                            ForEach(MemoryKind.allCases, id: \.self) { kind in
                                Text(kind.label).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                        .labelsHidden()
                    }

                    Toggle(isOn: $draft.enabled) {
                        Text("启用（拼进系统提示词）")
                            .font(.system(size: Theme.size(13)))
                            .foregroundStyle(Theme.dim)
                    }
                    .tint(Theme.accent)

                    if !isNew {
                        Button {
                            onDelete(draft)
                            dismiss()
                        } label: {
                            Text("删除这条")
                                .font(.system(size: Theme.size(13.5), weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(Theme.danger)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 99, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
    }
}