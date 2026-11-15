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
    let logs = LogStore()
    let logFile: LogFile

    var servers = ServersFile()
    var routing = RoutingFile.initial()
    var settings = AppSettings()
    var section: AppSection = .home

    /// Сообщение о повреждённом файле данных; пока оно есть, этот файл не перезаписывается.
    var loadError: String?
    private var readOnlyFiles: Set<String> = []

    var selectedServerId: String?
    /// Разобранная ссылка, ждущая подтверждения в панели импорта.
    var importDraft: ImportDraft?
    var importError: String?

    /// Ручная капча ждёт пользователя - на главной и в меню появляется «Пройти проверку».
    var captchaNeedsAttention = false
    private var captchaPresenter = CaptchaPresenter()
    private let captchaWindow = CaptchaWindowController()
    private let autoCaptcha = AutoCaptchaHost()

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
        logFile = LogFile(directory: store.directory.appendingPathComponent("logs"))
        connection = ConnectionController(
            core: { CoreProcess(binary: helper, stateDir: stateDir) },
            engine: { DaemonClient() },
            network: NetworkWatcher(),
            portPicker: PortPicker.freeUDPPort)

        servers = load(ServersFile.self, "servers.json", servers)
        routing = load(RoutingFile.self, "routing.json", routing).normalized()
        settings = load(AppSettings.self, "settings.json", settings)
        L10n.language = settings.language
        connection.onCaptchaChange = { [weak self] request in self?.handleCaptcha(request) }
        connection.onLog = { [weak self] line in self?.log(line) }
        // Метка в файле лога: по ней видно, где приложение перезапускали.
        log(LogLine(level: .info, source: .app, text: "FreeTurn запущен, ядро \(AppInfo.coreVersion), сеть \(SystemNetwork.current()?.ifName ?? "нет")"))
        // FREETURN_DEMO_CAPTCHA - показать окно капчи без подключения: для проверки интерфейса.
        if ProcessInfo.processInfo.environment["FREETURN_DEMO_CAPTCHA"] != nil {
            DispatchQueue.main.async { self.handleCaptcha(CaptchaRequest(url: "http://localhost:8765/", manual: true)) }
        }
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
        // Экранный лог - про текущую сессию; файл на диске хранит и прошлые.
        logs.clear()
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

    private static let logTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Строка лога: на экран и в файл. Секреты прячутся до записи, а не при показе.
    func log(_ line: LogLine) {
        var line = line
        if settings.privacyMode {
            line.text = Redactor.redact(line.text, secrets: secrets)
        } else if line.text.hasPrefix("Команда:") {
            // Команду запуска часто копируют в чаты: ссылку на звонок и ключи прячем всегда.
            line.text = Redactor.redact(line.text, secrets: secrets, maskAddresses: false)
        }
        logs.append(line)
        logFile.append("\(Self.logTime.string(from: line.date)) [\(line.source.rawValue)] [\(line.level.rawValue)] \(line.text)")
    }

    /// Секреты активного сервера, которые не ловятся по виду: ключи WireGuard, ссылка на звонок.
    private var secrets: [String] {
        guard let server = activeServer else { return [] }
        var list = [server.client.callLink, server.opts.obfKey, server.client.clientId]
        if let wg = try? WGConfig.parse(server.client.wireGuardConfig) {
            list.append(wg.privateKey)
            list += wg.peers.compactMap(\.presharedKey)
        }
        return list
    }

    private func handleCaptcha(_ request: CaptchaRequest?) {
        perform(captchaPresenter.action(for: request, target: settings.captchaTarget))
        captchaNeedsAttention = captchaPresenter.needsAttention
    }

    /// Открыть ручную капчу снова - после того как окно закрыли, не пройдя её.
    func reopenCaptcha() {
        perform(captchaPresenter.reopenAction(target: settings.captchaTarget))
    }

    private func perform(_ action: CaptchaAction) {
        switch action {
        case let .showWindow(url):
            autoCaptcha.clear()
            captchaWindow.show(url: url) {}
        case let .openBrowser(url):
            autoCaptcha.clear()
            captchaWindow.close()
            if let target = URL(string: url) { NSWorkspace.shared.open(target) }
        case let .loadHidden(url):
            captchaWindow.close()
            autoCaptcha.show(url: url)
        case .dismiss:
            captchaWindow.close()
            autoCaptcha.clear()
        case .none:
            break
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
