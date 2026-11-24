import SwiftUI
import DeepChatCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 酒馆：选角色卡 → 勾世界书条目 → 场景与开场白 → 用一句话开戏 / 续写。
/// 自带 `PersonaStore` + `WorldbookStore`，不依赖 `AppModel`，也不自己发网络请求：
/// 拼好的提示词通过 `onSend` / `onContinue` 交给调用方（聊天页），回调为 nil 时只在页内预览。
public struct TavernView: View {

    @StateObject private var personas = PersonaStore()
    @StateObject private var worldbook = WorldbookStore()

    /// 交给调用方：(系统设定块, 用户这一句)。
    let onSend: ((String, String) -> Void)?
    /// 交给调用方：场景续写用的整段提示词（设定 + 最近对话 + 续写指令）。
    let onContinue: ((String) -> Void)?

    @State private var forcedIDs: Set<UUID> = []
    @State private var input = ""
    @State private var draft = ""
    @State private var sceneText = ""
    @State private var greetingText = ""
    @State private var scanDepth = 6
    @State private var editingCard: PersonaCard?
    @State private var editingEntry: WorldbookEntry?
    @State private var preview = ""
    @State private var previewVisible = false
    @State private var notice = ""

    public init(onSend: ((String, String) -> Void)? = nil,
                onContinue: ((String) -> Void)? = nil) {
        self.onSend = onSend
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    cardSection
                    sceneSection
                    worldbookSection
                    transcriptSection
                    if previewVisible { previewSection }
                }
                .padding(16)
            }

            inputBar
        }
        .background(Theme.bg)
        .onAppear { syncFromCard() }
        .sheet(item: $editingCard) { card in
            PersonaEditorView(
                card: card,
                isNew: !personas.contains(card.id),
                onSave: { saved in
                    personas.update(saved)
                    if personas.selectedID == saved.id { syncFromCard() }
                    editingCard = nil
                },
                onDelete: { doomed in
                    personas.delete(id: doomed.id)
                    editingCard = nil
                }
            )
        }
        .sheet(item: $editingEntry) { entry in
            WorldbookEntryEditorView(
                entry: entry,
                isNew: !worldbook.contains(entry.id),
                onSave: { saved in
                    if worldbook.contains(saved.id) { worldbook.update(saved) } else { worldbook.add(saved) }
                    editingEntry = nil
                },
                onDelete: { doomed in
                    worldbook.delete(id: doomed.id)
                    forcedIDs.remove(doomed.id)
                    editingEntry = nil
                }
            )
        }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack {
            Text("酒馆")
                .font(.system(size: Theme.size(20), weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                continueScene()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.append")
                        .font(.system(size: 13, weight: .semibold))
                    Text("场景续写")
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

    // MARK: 角色卡

    private var selectedCard: PersonaCard? { personas.selectedCard }

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("角色卡")
                    .font(.system(size: Theme.size(12), weight: .semibold))
                    .foregroundStyle(Theme.faint)
                Spacer()
                Button {
                    editingCard = PersonaCard()
                } label: {
                    Text("＋ 新建")
                        .font(.system(size: Theme.size(12.5), weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            if personas.cards.isEmpty {
                Text("还没有角色卡。先建一张，写清楚他是谁、怎么说话，酒馆就按这个演。")
                    .font(.system(size: Theme.size(12.5)))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(personas.cards) { card in
                            cardChip(card)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if let card = selectedCard {
                HStack(spacing: 8) {
                    Text(card.displayName)
                        .font(.system(size: Theme.size(14), weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("已填 \(card.filledSectionCount) 节")
                        .font(.system(size: Theme.size(11.5)))
                        .foregroundStyle(Theme.faint)
                    Spacer()
                    Button {
                        editingCard = card
                    } label: {
                        Text("编辑这张卡")
                            .font(.system(size: Theme.size(12.5)))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func cardChip(_ card: PersonaCard) -> some View {
        let on = personas.selectedID == card.id
        return Button {
            personas.select(card.id)
            syncFromCard()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.displayName)
                    .font(.system(size: Theme.size(13.5), weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Theme.accent : Theme.ink)
                    .lineLimit(1)
                Text(card.scene.isEmpty ? "未设置场景" : card.scene)
                    .font(.system(size: Theme.size(10.5)))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(on ? Theme.accent.opacity(0.14) : Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(on ? Theme.accent.opacity(0.55) : Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 场景与开场白

    private var sceneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("场景与开场白")
                    .font(.system(size: Theme.size(12), weight: .semibold))
                    .foregroundStyle(Theme.faint)
                Spacer()
                if selectedCard != nil {
                    Button {
                        writeBackToCard()
                    } label: {
                        Text("写回卡片")
                            .font(.system(size: Theme.size(12.5), weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedCard == nil {
                Text("先选一张角色卡，场景与开场白会从卡上带过来。")
                    .font(.system(size: Theme.size(12.5)))
                    .foregroundStyle(Theme.dim)
            } else {
                labeledEditor("场景", text: $sceneText, hint: "发生在哪里、此刻的局面", height: 68)
                labeledEditor("开场白", text: $greetingText, hint: "第一句他说什么", height: 78)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: 世界书

    private var worldbookSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("世界书")
                    .font(.system(size: Theme.size(12), weight: .semibold))
                    .foregroundStyle(Theme.faint)
                Spacer()
                Text("命中 \(worldbook.match(in: scanText).count) 条")
                    .font(.system(size: Theme.size(11.5)))
                    .foregroundStyle(Theme.faint)
                Button {
                    editingEntry = WorldbookEntry(order: (worldbook.entries.map(\.order).max() ?? 0) + 1)
                } label: {
                    Text("＋ 新增")
                        .font(.system(size: Theme.size(12.5), weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            Text("勾选 = 本轮强制注入；不勾的按触发词自动匹配（触发词留空即常驻）。扫最近 \(scanDepth) 行。")
                .font(.system(size: Theme.size(11.5)))
                .foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)

            if worldbook.entries.isEmpty {
                Text("还没有条目。加一条「关键词 + 内容」，例如：北平 → 民国十七年的北平，冬天极冷。")
                    .font(.system(size: Theme.size(12.5)))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(worldbook.entries) { entry in
                worldbookRow(entry)
            }

            HStack(spacing: 8) {
                Text("扫描行数")
                    .font(.system(size: Theme.size(12)))
                    .foregroundStyle(Theme.dim)
                Slider(value: Binding(
                    get: { Double(scanDepth) },
                    set: { scanDepth = max(1, Int($0.rounded())) }
                ), in: 1...20, step: 1)
                .tint(Theme.accent)
                Text("\(scanDepth)")
                    .font(.system(size: Theme.size(12)))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 22)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func worldbookRow(_ entry: WorldbookEntry) -> some View {
        let forced = forcedIDs.contains(entry.id)
        return HStack(alignment: .top, spacing: 10) {
            Button {
                if forced { forcedIDs.remove(entry.id) } else { forcedIDs.insert(entry.id) }
            } label: {
                Image(systemName: forced ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(forced ? Theme.accent : Theme.faint)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: Theme.size(13.5), weight: .medium))
                    .foregroundStyle(entry.enabled ? Theme.ink : Theme.faint)
                    .lineLimit(1)
                if !entry.content.isEmpty {
                    Text(entry.content)
                        .font(.system(size: Theme.size(12)))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editingEntry = entry }

            Toggle("", isOn: Binding(
                get: { entry.enabled },
                set: { worldbook.setEnabled($0, id: entry.id) }
            ))
            .labelsHidden()
            .tint(Theme.accent)
        }
        .padding(10)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: 最近对话

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最近对话")
                    .font(.system(size: Theme.size(12), weight: .semibold))
                    .foregroundStyle(Theme.faint)
                Spacer()
                Text("\(lineCount) 行")
                    .font(.system(size: Theme.size(11.5)))
                    .foregroundStyle(Theme.faint)
            }
            labeledEditor("", text: $draft, hint: "把上一段贴进来，或写「他说……我……」；世界书按末尾 \(scanDepth) 行匹配", height: 96)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: 提示词预览

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("拼好的提示词")
                .font(.system(size: Theme.size(12), weight: .semibold))
                .foregroundStyle(Theme.faint)
            Text(preview.isEmpty ? "没有可拼的内容：先选角色卡，或勾一条世界书。" : preview)
                .font(.system(size: Theme.size(11.5), design: .monospaced))
                .foregroundStyle(Theme.dim)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 8) {
                GhostButton("复制") { copyToClipboard(preview); notice = "已复制提示词" }
                GhostButton("收起") { previewVisible = false }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: 底部输入

    private var inputBar: some View {
        VStack(spacing: 6) {
            if !notice.isEmpty {
                Text(notice)
                    .font(.system(size: Theme.size(11.5)))
                    .foregroundStyle(Theme.ok)
            }
            HStack(spacing: 10) {
                TextField("说一句，或写一个动作…", text: $input)
                    .font(.system(size: Theme.size(14)))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 99, style: .continuous))

                Button {
                    startScene()
                } label: {
                    Text("发起剧情")
                        .font(.system(size: Theme.size(14), weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.surface2 : Theme.accent)
                        .foregroundStyle(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.faint : Theme.accentInk)
                        .clipShape(RoundedRectangle(cornerRadius: 99, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.surface)
    }

    // MARK: 拼装

    private var lineCount: Int {
        draft.split(separator: "\n", omittingEmptySubsequences: true).count
    }

    /// 世界书扫描用的文本：最近对话 + 这一句输入。
    private var scanText: String {
        let parts = [draft, input].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return parts.joined(separator: "\n")
    }

    /// 人设段：卡上 select 的小节 + 本页覆盖后的场景/开场白。
    /// 开场白只在没有最近对话时注入（有草稿说明戏已经开了）。
    private func personaBlock() -> String {
        guard var card = selectedCard else { return "" }
        card.scene = sceneText.trimmingCharacters(in: .whitespacesAndNewlines)
        card.greeting = greetingText.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [PersonaSection] = [.selfIntro, .personality, .speechHabits, .neverSay, .examples, .scene]
        if lineCount == 0 { sections.append(.greeting) }
        return card.render(sections: sections, charName: card.displayName, userName: "你")
    }

    /// 完整系统设定：人设段 + 世界书块。上层拿它当 system message。
    public func systemBlock() -> String {
        var parts: [String] = []
        let persona = personaBlock()
        if !persona.isEmpty { parts.append(persona) }
        let world = worldbook.prompt(matching: scanText, scanDepth: scanDepth, forced: Array(forcedIDs))
        if !world.isEmpty { parts.append(world) }
        return parts.joined(separator: "\n\n")
    }

    /// 场景续写：设定 + 最近对话 + 一句续写指令，整段给调用方（或页内预览）。
    public func continuePrompt() -> String {
        let system = systemBlock()
        var parts: [String] = []
        if !system.isEmpty { parts.append(system) }
        let recent = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !recent.isEmpty { parts.append("【最近发生的事】\n" + recent) }
        parts.append("接着上面往下写一段：不要替我说话，只写这个人的台词与动作，保持他的口气，不加解释。")
        return parts.joined(separator: "\n\n")
    }

    private func startScene() {
        let line = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        guard selectedCard != nil else {
            notice = "先选一张角色卡"
            return
        }
        let system = systemBlock()
        draft = draft.isEmpty ? "你：\(line)" : draft + "\n你：\(line)"
        input = ""
        if let onSend {
            onSend(system, line)
            notice = "已交给对话页：共 \(system.count) 字设定"
        } else {
            preview = "【system】\n\(system)\n\n【user】\n\(line)"
            previewVisible = true
            notice = ""
        }
    }

    private func continueScene() {
        let prompt = continuePrompt()
        if let onContinue {
            onContinue(prompt)
            notice = "已交给对话页续写"
        } else {
            preview = prompt
            previewVisible = true
            notice = ""
        }
    }

    // MARK: 小工具

    private func syncFromCard() {
        guard let card = selectedCard else {
            sceneText = ""
            greetingText = ""
            return
        }
        sceneText = card.scene
        greetingText = card.greeting
    }

    private func writeBackToCard() {
        guard var card = selectedCard else { return }
        card.scene = sceneText.trimmingCharacters(in: .whitespacesAndNewlines)
        card.greeting = greetingText.trimmingCharacters(in: .whitespacesAndNewlines)
        personas.update(card)
        notice = "场景与开场白已写回「\(card.displayName)」"
    }

    private func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func labeledEditor(_ label: String, text: Binding<String>, hint: String, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: Theme.size(11.5)))
                    .foregroundStyle(Theme.faint)
            }
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(hint)
                        .font(.system(size: Theme.size(13)))
                        .foregroundStyle(Theme.faint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(.system(size: Theme.size(14)))
                    .foregroundColor(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: height)
            }
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - 世界书条目编辑器

private struct WorldbookEntryEditorView: View {

    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    let onSave: (WorldbookEntry) -> Void
    let onDelete: (WorldbookEntry) -> Void

    @State private var draft: WorldbookEntry

    init(entry: WorldbookEntry,
         isNew: Bool,
         onSave: @escaping (WorldbookEntry) -> Void,
         onDelete: @escaping (WorldbookEntry) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: entry)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                    .font(.system(size: Theme.size(14)))
                    .foregroundStyle(Theme.dim)
                    .buttonStyle(.plain)
                Spacer()
                Text(isNew ? "新增世界书条目" : "编辑世界书条目")
                    .font(.system(size: Theme.size(15), weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("保存") {
                    if draft.isBlank { return }
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
                        Text("触发词（逗号分隔，留空即常驻）")
                            .font(.system(size: Theme.size(11.5)))
                            .foregroundStyle(Theme.faint)
                        TextField("北平, 茶馆", text: keysBinding)
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
                                Text("这条世界观规矩：地名、势力、规则，一两句说清")
                                    .font(.system(size: Theme.size(13)))
                                    .foregroundStyle(Theme.faint)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 11)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $draft.content)
                                .font(.system(size: Theme.size(14)))
                                .foregroundColor(Theme.ink)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .frame(minHeight: 130)
                        }
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Toggle(isOn: $draft.enabled) {
                        Text("启用")
                            .font(.system(size: Theme.size(13)))
                            .foregroundStyle(Theme.dim)
                    }
                    .tint(Theme.accent)

                    Stepper(value: $draft.order, in: 0...99) {
                        Text("注入顺序：\(draft.order)")
                            .font(.system(size: Theme.size(13)))
                            .foregroundStyle(Theme.dim)
                    }

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

    private var keysBinding: Binding<String> {
        Binding(
            get: { draft.keysText },
            set: { draft.keys = WorldbookEntry.parseKeys($0) }
        )
    }
}