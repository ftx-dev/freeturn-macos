import SwiftUI
import FreeTurnKit

struct ServersView: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: Server?
    @State private var newName = ""
    @State private var deleting: Server?

    var body: some View {
        @Bindable var model = model
        // Фиксированная колонка списка: HSplitView внутри NavigationSplitView вылезал за края окна.
        HStack(spacing: 0) {
            List(selection: $model.selectedServerId) {
                ForEach(model.servers.list) { server in
                    ServerRow(server: server, active: server.id == model.servers.activeId)
                        .tag(server.id)
                        .contextMenu { rowMenu(server) }
                }
            }
            .frame(width: 250)
            .overlay {
                if model.servers.list.isEmpty {
                    ContentUnavailableView(L("Нет серверов"), systemImage: "server.rack",
                                           description: Text(L("Вставьте ссылку freeturn:// или добавьте сервер вручную")))
                }
            }

            Divider()

            Group {
                if let id = model.selectedServerId, model.servers.list.contains(where: { $0.id == id }) {
                    ServerDetailView(serverId: id)
                } else {
                    ContentUnavailableView(L("Выберите сервер"), systemImage: "sidebar.left")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            // Разделы живут скрытыми (см. RootView): кнопки панели - только у видимого.
            if model.section == .servers {
                ToolbarItem {
                    Menu {
                        Button(L("Вставить из буфера"), systemImage: "doc.on.clipboard") { model.importFromPasteboard() }
                        Button(L("QR-код из файла…"), systemImage: "qrcode") { model.importQRFromFile() }
                        Button(L("QR-код с экрана"), systemImage: "qrcode.viewfinder") { model.importQRFromScreen() }
                        Divider()
                        Button(L("Ручная настройка"), systemImage: "square.and.pencil") { model.addManualServer() }
                        Button(L("Восстановить из резервной копии…"), systemImage: "clock.arrow.circlepath") { model.section = .settings }
                    } label: {
                        Label(L("Добавить сервер"), systemImage: "plus")
                    }
                }
            }
        }
        .onAppear { if model.selectedServerId == nil { model.selectedServerId = model.servers.activeId } }
        .alert(L("Переименовать сервер"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("Имя сервера"), text: $newName)
            Button(L("Сохранить")) {
                if let renaming { model.servers.rename(id: renaming.id, to: newName); model.persist() }
            }
            Button(L("Отмена"), role: .cancel) {}
        }
        .confirmationDialog(L("Удалить сервер?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { server in
            Button(L("Удалить"), role: .destructive) {
                model.servers.remove(id: server.id)
                model.persist()
            }
        } message: { server in
            Text(String(format: L("Сервер «%@» и все его настройки будут удалены из приложения."), server.name))
        }
    }

    @ViewBuilder private func rowMenu(_ server: Server) -> some View {
        let busy = model.connection.state.isActive
        Button(L("Сделать активным")) { model.setActive(server.id) }
            .disabled(busy || server.id == model.servers.activeId)
        Button(L("Переименовать")) { newName = server.name; renaming = server }
        Button(L("Поделиться…")) { model.sharing = server }
            .disabled(server.client.serverAddress.isEmpty)
        Button(L("Клонировать")) { model.servers.clone(id: server.id); model.persist() }
        Divider()
        Button(L("Удалить"), role: .destructive) { deleting = server }
            // Сервер под живым подключением удалять нельзя.
            .disabled(busy && server.id == model.connection.activeServerId)
    }
}

private struct ServerRow: View {
    @Environment(AppModel.self) private var model
    let server: Server
    let active: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: server.client.provider == Provider.direct ? "arrow.right" : "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name.isEmpty ? L("Без названия") : server.name).fontWeight(.medium)
                Text(server.client.serverAddress.isEmpty ? "—" : model.masked(server.client.serverAddress))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if active {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .help(L("Активный"))
            }
        }
        .padding(.vertical, 3)
    }
}
