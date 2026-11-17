import SwiftUI
import FreeTurnKit

/// SOCKS5-клиент (раздел «Экспериментальное»): держит свой сеанс службы, отдельно от основного подключения.
@MainActor @Observable
final class Socks5Client {
    enum State: Equatable { case off, starting, on(String), failed(String) }

    static let shared = Socks5Client()

    private(set) var state: State = .off
    @ObservationIgnored private var daemon: DaemonClient?

    var isActive: Bool {
        switch state {
        case .starting, .on: true
        default: false
        }
    }

    func connect(_ config: Socks5ClientConfig, debug: Bool) {
        guard !isActive else { return }
        config.save()
        state = .starting
        let daemon = DaemonClient()
        self.daemon = daemon
        daemon.onEvent = { [weak self] event in
            guard let self, self.daemon === daemon, case let .exited(code, tail) = event else { return }
            self.finish(.failed(tail.isEmpty ? String(format: L("Движок завершился с кодом %d"), code) : tail))
        }
        Task {
            do {
                // Старая служба не знает конфиг SOCKS5 - просим её обновить, а не показываем ошибку конфига.
                let status = try await daemon.status()
                guard status.version == DaemonProtocol.version else {
                    finish(.failed(L("Служба устарела: переустановите её в Настройках → Фоновая служба.")))
                    return
                }
                // Прокси должен ответить по SOCKS5 - иначе честная ошибка, а не «Подключено» без интернета.
                if let problem = await Task.detached(operation: { Socks5Probe.check(config) }).value {
                    finish(.failed(problem))
                    return
                }
                let engine = try config.engineConfig(mtu: CoreConfig.tunnelMTU, debug: debug)
                try await daemon.start(config: engine)
                if self.daemon === daemon { state = .on(config.address) }
            } catch DaemonError.notInstalled {
                finish(.failed(L("Фоновая служба не установлена.")))
            } catch DaemonError.busy {
                finish(.failed(L("Служба занята: сначала отключите основное подключение.")))
            } catch {
                finish(.failed("\(error)"))
            }
        }
    }

    func disconnect() {
        guard let daemon else { state = .off; return }
        Task {
            await daemon.stop()
            finish(.off)
        }
    }

    private func finish(_ final: State) {
        daemon?.close()
        daemon = nil
        state = final
    }
}

/// Строка в настройках: состояние и кнопка, открывающая окно подключения.
struct Socks5ClientRow: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false
    private var client: Socks5Client { .shared }

    var body: some View {
        LabeledContent {
            Button(client.isActive ? L("Отключить") : L("Подключить…")) {
                if client.isActive { client.disconnect() } else { editing = true }
            }
            .disabled(!client.isActive && model.connection.state.isActive)
        } label: {
            Text(L("SOCKS5-клиент"))
            Text(subtitle)
        }
        .sheet(isPresented: $editing) { Socks5ClientSheet() }
    }

    private var subtitle: String {
        switch client.state {
        case .off:
            model.connection.state.isActive
                ? L("Недоступен, пока работает основное подключение.")
                : L("Весь трафик Mac - через SOCKS5, например через SOCKS5 Hotspot телефона в той же Wi-Fi сети.")
        case .starting: L("Подключение…")
        case let .on(address): String(format: L("Подключено через %@"), address)
        case let .failed(reason): String(format: L("Не удалось: %@"), reason)
        }
    }
}

private struct Socks5ClientSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var config = Socks5ClientConfig.load()
    @State private var port = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("SOCKS5-клиент")).font(.title2.weight(.semibold))
            Text(L("Mac и телефон с включённым SOCKS5 Hotspot должны быть в одной Wi-Fi сети; адрес - из QR SOCKS5 Hotspot на телефоне. Если Mac подключён к точке доступа телефона, включите на телефоне «Раздачу через Shizuku» - SOCKS5 не нужен."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                TextField(L("Адрес"), text: $config.host)
                TextField(L("Порт"), text: $port)
                TextField(L("Логин (необязательно)"), text: $config.user)
                SecureField(L("Пароль"), text: $config.password)
            }
            HStack {
                Spacer()
                Button(L("Отмена"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Подключить")) {
                    Socks5Client.shared.connect(config, debug: model.settings.debugScreen)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!config.isValid)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { port = String(config.port) }
        .onChange(of: port) { _, text in config.port = Int(text.filter(\.isNumber)) ?? 0 }
    }
}
