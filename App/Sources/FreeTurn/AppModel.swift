import Foundation
import Observation
import SwiftUI
import FreeTurnKit

enum AppSection: String, CaseIterable, Identifiable {
    case home, servers, routing, logs, settings
    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .home: L("Главная")
        case .servers: L("Серверы")
        case .routing: L("Маршруты")
        case .logs: L("Логи")
        case .settings: L("Настройки")
        }
    }

    var icon: String {
        switch self {
        case .home: "power.circle"
        case .servers: "server.rack"
        case .routing: "arrow.triangle.branch"
        case .logs: "text.alignleft"
        case .settings: "gearshape"
        }
    }
}

/// Состояние приложения: данные на диске и текущее подключение.
@MainActor @Observable
final class AppModel {
    let store: Store
    let connection: ConnectionController

    var servers = ServersFile()
    var routing = RoutingFile(profiles: [Presets.allViaVPN, Presets.russiaDirect], sharedProfileId: Presets.allViaVPN.id)
    var settings = AppSettings()
    var section: AppSection = .home

    /// Сообщение о повреждённом файле данных; пока оно есть, этот файл не перезаписывается.
    var loadError: String?
    private var readOnlyFiles: Set<String> = []

    var selectedServerId: String?
    /// Разобранная ссылка, ждущая подтверждения в панели импорта.
    var importDraft: ImportDraft?
    var importError: String?

    var installingDaemon = false
    var daemonInstallError: String?

    /// FREETURN_DATA_DIR - другой каталог данных: для разработки и проверок, чтобы не трогать настоящий.
    static var dataDirectory: URL {
        ProcessInfo.processInfo.environment["FREETURN_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? Store.defaultDirectory
    }

    init(store: Store = Store(directory: AppModel.dataDirectory)) {
        self.store = store
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/freeturn-core")
        let stateDir = store.directory.appendingPathComponent("core-state")
        connection = ConnectionController(
            core: { CoreProcess(binary: helper, stateDir: stateDir) },
            engine: { DaemonClient() },
            network: NetworkWatcher(),
            portPicker: PortPicker.freeUDPPort)

        servers = load(ServersFile.self, "servers.json", servers)
        routing = load(RoutingFile.self, "routing.json", routing)
        settings = load(AppSettings.self, "settings.json", settings)
        L10n.language = settings.language
        // FREETURN_SECTION - открыть приложение сразу на нужном разделе: для проверок интерфейса.
        if let raw = ProcessInfo.processInfo.environment["FREETURN_SECTION"], let start = AppSection(rawValue: raw) {
            section = start
        }
    }

    private func load<T: Decodable>(_ type: T.Type, _ name: String, _ fallback: T) -> T {
        do {
            return try store.load(type, from: name, default: fallback)
        } catch {
            readOnlyFiles.insert(name)
            loadError = String(format: L("Файл %@ повреждён. Изменения не сохраняются, чтобы не затереть его. Исправьте или удалите файл и перезапустите приложение."), name)
            return fallback
        }
    }

    func persist() {
        save(servers, "servers.json")
        save(routing, "routing.json")
        save(settings, "settings.json")
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        guard !readOnlyFiles.contains(name) else { return }
        try? store.save(value, to: name)
    }

    var activeServer: Server? { servers.active }
    var activeProfile: RoutingProfile? { activeServer.map(routing.profile(for:)) }

    func setActive(_ id: String) {
        guard !connection.state.isActive else { return }
        servers.activeId = id
        persist()
    }

    func toggleConnection() {
        Task {
            if connection.state.isActive {
                await connection.disconnect()
            } else {
                await connect()
            }
        }
    }

    func connect() async {
        guard let server = activeServer else { return }
        let clientId = (try? store.ownClientId()) ?? ""
        await connection.connect(server: server, profile: routing.profile(for: server),
                                 settings: settings, ownClientId: clientId)
    }

    /// Ставит службу и, если получилось, сразу продолжает подключение.
    func installDaemonAndConnect() {
        guard !installingDaemon else { return }
        installingDaemon = true
        daemonInstallError = nil
        Task {
            defer { installingDaemon = false }
            do {
                try await DaemonInstaller.install()
                await connect()
            } catch DaemonInstallError.cancelled {
                // Передумал - не ошибка.
            } catch let DaemonInstallError.failed(message) {
                daemonInstallError = String(format: L("Не удалось установить службу: %@"), message)
            } catch {
                daemonInstallError = String(format: L("Не удалось установить службу: %@"), "\(error)")
            }
        }
    }

    /// Приватный режим: адреса на экране заменяются точками.
    func masked(_ address: String) -> String {
        settings.privacyMode ? "•••••••" : address
    }

    var colorScheme: ColorScheme? {
        switch settings.theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    func text(for failure: ConnectionFailure) -> String {
        switch failure {
        case .noAddress: L("У сервера не указан адрес")
        case .noCallLink: L("Для Relay нужна ссылка на звонок")
        case .noWireGuard: L("Добавьте конфиг WireGuard, чтобы подключиться")
        case .badWireGuard: L("Не удалось разобрать конфиг WireGuard")
        case .invalidRule: L("В профиле маршрутов есть некорректное правило")
        case .noNetwork: L("Нет сети")
        case .daemonNotInstalled: L("Нужна фоновая служба")
        case .daemonVersionMismatch: L("Служба устарела")
        case .daemonBusy: L("Службой сейчас управляет другое приложение")
        case let .core(message): String(format: L("Ядро: %@"), message)
        case let .engine(message): String(format: L("Туннель: %@"), message)
        }
    }
}
