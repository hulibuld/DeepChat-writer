import SwiftUI
import DeepChatCore

public struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var exportMessage = ""

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("会话")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    model.newSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface)

            List {
                ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, session in
                    Button {
                        model.currentIndex = index
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.system(size: 15, weight: index == model.currentIndex ? .semibold : .regular))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text("\(session.mode.label) · \(session.messages.count) 条 · \(dateText(session.updatedAt))")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.faint)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.bg)
                }
                .onDelete { offsets in
                    model.delete(at: offsets)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)

            if !exportMessage.isEmpty {
                Text(exportMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .padding(.bottom, 8)
            }
        }
        .background(Theme.bg)
        .toolbar {
            Button("导出当前") { exportCurrent() }
        }
    }

    private func exportCurrent() {
        let md = Exporter.markdown(model.current)
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let url = try Exporter.write(md, name: model.current.title, to: folder)
            exportMessage = "已导出到「文件」App：\(url.lastPathComponent)"
        } catch {
            exportMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}