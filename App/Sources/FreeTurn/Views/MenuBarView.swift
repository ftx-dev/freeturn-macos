import SwiftUI
import FreeTurnKit

/// Меню иконки в строке меню.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let state = model.connection.state
        Text(statusLine(state))
        if case .connected = state {
            let stats = model.connection.stats
            Text("↓ \(Formatters.rate(stats.rxRate, style: L10n.unitStyle))   ↑ \(Formatters.rate(stats.txRate, style: L10n.unitStyle))")
        }
        Divider()
        if model.captchaNeedsAttention {
            Button(L("Пройти проверку")) { model.reopenCaptcha() }
        }
        Button(state.isActive ? L("Отключить") : L("Подключить")) { model.toggleConnection() }
            .disabled(model.activeServer == nil || state == .stopping)
        if !model.servers.list.isEmpty {
            Menu(L("Сервер")) {
                ForEach(model.servers.list) { server in
                    Button {
                        model.setActive(server.id)
                    } label: {
                        if server.id == model.servers.activeId { Label(server.name, systemImage: "checkmark") } else { Text(server.name) }
                    }
                }
            }
            .disabled(state.isActive)
        }
        Divider()
        Button(L("Открыть FreeTurnX")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(L("Выйти")) {
            Task {
                await model.connection.disconnect()
                NSApp.terminate(nil)
            }
        }
        .keyboardShortcut("q")
    }

    private func statusLine(_ state: ConnectionState) -> String {
        switch state {
        case .off: "FreeTurnX"
        case .starting: L("Запуск…")
        case .connecting: L("Подключение…")
        case .captcha: L("Проверка CAPTCHA")
        case .connected: "\(L("Подключено")) — \(model.activeServer?.name ?? "")"
        case .stopping: L("Отключение…")
        case .failed: L("Ошибка")
        }
    }

    static func icon(for state: ConnectionState) -> String {
        switch state {
        case .off: "shield.slash"
        case .starting, .connecting, .stopping: "arrow.triangle.2.circlepath"
        case .captcha: "exclamationmark.shield"
        case .connected: "checkmark.shield.fill"
        case .failed: "xmark.shield"
        }
    }
}
