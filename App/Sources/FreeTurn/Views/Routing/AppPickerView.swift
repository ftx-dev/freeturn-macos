import SwiftUI
import FreeTurnKit

/// Выбор приложения для правила: запущенные сверху, поиск по имени.
struct AppPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void
    @State private var apps: [AppEntry] = []
    @State private var query = ""

    private var filtered: [AppEntry] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(L("Поиск приложений"), text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            List(filtered) { app in
                Button {
                    onPick(app.id)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.id))
                            .resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                            Text(app.id).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if app.isRunning {
                            Text(L("запущено")).font(.caption).foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if filtered.isEmpty { ContentUnavailableView(L("Приложения не найдены"), systemImage: "magnifyingglass") }
            }
            HStack {
                Spacer()
                Button(L("Отмена"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 520)
        .onAppear { apps = InstalledApps.list() }
    }
}
