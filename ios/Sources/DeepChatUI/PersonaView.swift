import SwiftUI
import DeepChatCore

/// 角色卡：列表 → 编辑 → 选中后按小节拼进系统提示词。
/// 本视图自带 `@StateObject`，不依赖 `AppModel`。
public struct PersonaView: View {

    @StateObject private var store = PersonaStore()
    @State private var editing: PersonaCard?
    @State private var promptVisible = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    cardsBlock
                    sectionsBlock
                    promptBlock
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
        .sheet(item: $editing) { card in
            PersonaEditorView(
                card: card,
                isNew: !store.contains(card.id),
                onSave: { saved in
                    store.update(saved)
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
            Text("角色卡")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                editing = PersonaCard()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("新建")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }

    // MARK: 卡列表

    private var cardsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我的角色卡")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                Spacer()
                Text("\(store.cards.count) 张")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faint)
            }

            if store.cards.isEmpty {
                Text("还没有角色卡。点右上角「新建」从姓名、人设、口头禅、禁忌、开场白开始；选中一张后，它的小节会拼进对话的系统提示词。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            }

            ForEach(store.cards) { card in
                cardRow(card)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func cardRow(_ card: PersonaCard) -> some View {
        let selected = store.selectedID == card.id
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.displayName)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("身份：\(card.scene.isEmpty ? "未设置" : card.scene)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                Text("已填小节：\(card.filledSectionCount) / \(PersonaSection.allCases.count)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editing = card }

            Button {
                store.select(selected ? nil : card.id)
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(selected ? Theme.accent : Theme.faint)
            }
            .buttonStyle(.plain)

            Button {
                editing = card
            } label: {
                Text("›")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.faint)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: 注入小节

    private var sectionsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("注入小节")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.faint)

            Text(store.selectedCard == nil
                 ? "先在上面选中一张卡；勾选的小节才会拼进提示词。"
                 : "当前卡：\(store.selectedCard?.displayName ?? "")。勾选的小节才会拼进提示词。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)

            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(PersonaSection.allCases, id: \.self) { section in
                    sectionPill(section)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func sectionPill(_ section: PersonaSection) -> some View {
        let on = store.isEnabled(section)
        return Button {
            store.toggle(section)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(on ? Theme.accent : Theme.faint)
                Text(section.label)
                    .font(.system(size: 13))
                    .foregroundStyle(on ? Theme.ink : Theme.dim)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 提示词预览

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("拼好的系统提示词")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                Spacer()
                Button(promptVisible ? "收起" : "预览") {
                    promptVisible.toggle()
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }

            if promptVisible {
                let composed = store.systemPrompt(basedOn: Prompts.system(for: .normal))
                Text(composed.isEmpty ? "还没选中卡，或勾选的小节全为空。" : composed)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.dim)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

// MARK: - 编辑器

private struct PersonaEditorView: View {

    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    let onSave: (PersonaCard) -> Void
    let onDelete: (PersonaCard) -> Void

    @State private var draft: PersonaCard

    init(card: PersonaCard,
         isNew: Bool,
         onSave: @escaping (PersonaCard) -> Void,
         onDelete: @escaping (PersonaCard) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: card)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dim)
                    .buttonStyle(.plain)
                Spacer()
                Text(isNew ? "新建角色卡" : "编辑角色卡")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("保存") {
                    draft.name = trimmed(draft.name)
                    draft.scene = trimmed(draft.scene)
                    draft.greeting = trimmed(draft.greeting)
                    onSave(draft)
                    dismiss()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    line("角色名", text: $draft.name)
                    block("场景 / 身份", text: $draft.scene, hint: "例如：民国北平的一家茶馆", height: 64)
                    block("自述", text: $draft.selfIntro, hint: "我是谁", height: 110)
                    block("性格", text: $draft.personality, hint: "说话行事方式", height: 100)
                    block("口癖 / 口头禅", text: $draft.speechHabits, hint: "常说的话、语气", height: 90)
                    block("禁忌 · 不会说的话", text: $draft.neverSay, hint: "绝不会说的话（防角色漂移）", height: 90)
                    block("开场白", text: $draft.greeting, hint: "第一句话怎么说", height: 100)
                    block("对话示例", text: $draft.examples, hint: "一段真实说话样例", height: 120)

                    if !isNew {
                        Button {
                            onDelete(draft)
                            dismiss()
                        } label: {
                            Text("删除这张卡")
                                .font(.system(size: 13.5, weight: .medium))
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

    private func line(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faint)
            TextField("例如：沉稳的编辑", text: text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .padding(10)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func block(_ label: String, text: Binding<String>, hint: String, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faint)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(hint)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.faint)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: height)
            }
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}