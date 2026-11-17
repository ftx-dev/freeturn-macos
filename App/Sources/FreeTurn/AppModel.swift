import Foundation
import Observation
import SwiftUI
import FreeTurnKit

enum AppSection: String, CaseIterable, Identifiable {
    case home, servers, routing, logs, settings, about
    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .home: L("Главная")
        case .servers: L("Серверы")
        case .routing: L("Маршруты")
        case .logs: L("Логи")
        case .settings: L("Настройки")
        case .about: L("О проекте")
        }
    }

    var icon: String {
        switch self {
        case .home: "power.circle"
        case .servers: "server.rack"
        case .routing: "arrow.triangle.branch"
        case .logs: "text.alignleft"
        case .settings: "gearshape"
        case .about: "info.circle"
        }
    }
}

/// Состояние приложения: данные на диске и текущее подключение.
@MainActor @Observable
final class AppModel {
    static let telegramURL = URL(string: "https://t.me/+ZVdbpZB0w_Q1MTdi")!

    let store: Store
    let connection: ConnectionController
    let logs = LogStore()
    let updater = Updater()
    /// Найдено обновление при запуске - показать предложение один раз.
    var offerUpdate: AvailableUpdate?
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

    /// Разовое предложение подписаться на Telegram-канал - после первого удачного подключения.
    var offerTelegram = false
    var sharing: Server?
    var backupMessage: String?

    var installingDaemon = false
    var daemonInstallError: String?
    var daemonStatusText = "…"
    /// Задержка через туннель, мс; nil - не измерена или нет ответа.
    var pingMs: Int?
    private var sleepWatcher: SleepWatcher?

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
        // NSApp появляется только после запуска приложения, а модель создаётся раньше.
        let icon = settings.appIcon
        let menuBarOnly = settings.menuBarOnly
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                AppIcons.apply(icon)
                AppModel.applyDockPolicy(menuBarOnly: menuBarOnly)
            }
        }
        connection.onCaptchaChange = { [weak self] request in self?.handleCaptcha(request) }
        connection.onLog = { [weak self] line in self?.log(line) }
        connection.onStateChange = { [weak self] state in self?.stateChanged(state) }
        sleepWatcher = SleepWatcher { [weak self] slept in self?.connection.systemDidWake(sleptSeconds: slept) }
        if settings.checkUpdates {
            Task {
                await updater.check()
                offerUpdate = updater.available
            }
        }
        if AutoConnect.shouldConnect(settings: settings, hasActiveServer: activeServer != nil) {
            Task { await self.connect() }
        }
        // Метка в файле лога: по ней видно, где приложение перезапускали.
        log(LogLine(level: .info, source: .app, text: "FreeTurnX запущен, ядро \(AppInfo.coreVersion), сеть \(SystemNetwork.current()?.ifName ?? "нет")"))
        // FREETURN_DEMO_CAPTCHA - показать окно капчи без подключения: для проверки интерфейса.
        if ProcessInfo.processInfo.environment["FREETURN_DEMO_CAPTCHA"] != nil {
            DispatchQueue.main.async { self.handleCaptcha(CaptchaRequest(url: "http://localhost:8765/", manual: true)) }
        }
        // FREETURN_DEMO_SHARE - сразу открыть «Поделиться» для активного сервера: для проверки интерфейса.
        if ProcessInfo.processInfo.environment["FREETURN_DEMO_SHARE"] != nil {
            DispatchQueue.main.async { self.sharing = self.activeServer }
        }
        // FREETURN_DEMO_UPDATE=<файл с заметками> - показать предложение обновиться: для проверки интерфейса.
        if let path = ProcessInfo.processInfo.environment["FREETURN_DEMO_UPDATE"], let notes = try? String(contentsOfFile: path, encoding: .utf8),
           let fake = URL(string: "https://github.com/ftx-dev/freeturn-macos/releases/latest") {
            DispatchQueue.main.async {
                self.offerUpdate = AvailableUpdate(version: "0.2.2", dmgURL: fake, checksumsURL: nil, pageURL: fake, notes: notes)
            }
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

    /// Текущий режим окна для кода вне SwiftUI (AppDelegate подгоняет размер при показе окна).
    @MainActor static var compactWindowSetting = false

    /// Без значка в Dock приложение живёт в строке меню; окно при этом открывается как обычно.
    @MainActor static func applyDockPolicy(menuBarOnly: Bool) {
        NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
        if !menuBarOnly { NSApp.activate(ignoringOtherApps: true) }
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

    /// Переключиться на другой сервер, как туннели у WireGuard: если подключены - переподключиться к нему.
    func switchServer(to id: String) {
        guard id != servers.activeId else { return }
        Task {
            let wasActive = connection.state.isActive
            if wasActive { await connection.disconnect() }
            servers.activeId = id
            persist()
            if wasActive { await connect() }
        }
    }

    func toggleConnection() {
        // SOCKS5-клиент показывается как подключение: кнопка и переключатель гасят его.
        if Socks5Client.shared.isActive { Socks5Client.shared.disconnect(); return }
        Task {
            if connection.state.isActive {
                // Выключил сам - при следующем запуске не восстанавливаем.
                settings.wasConnected = false
                persist()
                await connection.disconnect()
            } else {
                await connect()
            }
        }
    }

    func connect() async {
        // Пока работает SOCKS5-клиент, основное подключение не запускается (и наоборот).
        guard let server = activeServer, !Socks5Client.shared.isActive else { return }
        // Экранный лог - про текущую сессию; файл на диске хранит и прошлые.
        logs.clear()
        let clientId = (try? store.ownClientId()) ?? ""
        await connection.connect(server: server, profile: routing.profile(for: server),
                                 settings: settings, ownClientId: clientId)
    }

    private func stateChanged(_ state: ConnectionState) {
        switch state {
        case .connected:
            if !settings.wasConnected {
                settings.wasConnected = true
                persist()
                measurePing()
            }
            // Как на Android: один раз, после первого удачного подключения.
            if !settings.telegramPromptShown {
                settings.telegramPromptShown = true
                persist()
                offerTelegram = true
            }
        case .failed:
            // Сбой сам не пройдёт: автоподключение при запуске упёрлось бы в него же.
            settings.wasConnected = false
            persist()
            pingMs = nil
        case .off:
            pingMs = nil
        default:
            break
        }
    }

    func measurePing() {
        Task { pingMs = await PingMeter.measure() }
    }

    var redactedLaunchArgs: String {
        Redactor.redact(connection.launchArgs, secrets: secrets, maskAddresses: settings.privacyMode)
    }

    func refreshDaemonStatus() async {
        if connection.state.isActive {
            // Служба обслуживает одного клиента - наше же подключение.
            daemonStatusText = L("Работает")
            return
        }
        let client = DaemonClient()
        defer { client.close() }
        do {
            let status = try await client.status()
            daemonStatusText = status.version == DaemonProtocol.version
                ? L("Установлена")
                : L("Установлена другая версия — нужна переустановка")
        } catch DaemonError.notInstalled {
            daemonStatusText = L("Не установлена")
        } catch DaemonError.busy {
            daemonStatusText = L("Занята другим приложением")
        } catch {
            daemonStatusText = L("Не отвечает")
        }
    }

    func reinstallDaemon() { runDaemonTask { try await DaemonInstaller.install() } }
    func uninstallDaemon() { runDaemonTask { try await DaemonInstaller.uninstall() } }

    private func runDaemonTask(_ work: @escaping () async throws -> Void) {
        guard !installingDaemon else { return }
        installingDaemon = true
        daemonInstallError = nil
        Task {
            defer { installingDaemon = false }
            do {
                try await work()
            } catch DaemonInstallError.cancelled {
            } catch let DaemonInstallError.failed(message) {
                daemonInstallError = message
            } catch {
                daemonInstallError = "\(error)"
            }
            await refreshDaemonStatus()
        }
    }

    func installUpdate(_ update: AvailableUpdate) {
        Task { await updater.install(update) { await self.connection.disconnect() } }
    }

    /// Удаляет данные приложения. Только свои файлы поимённо: каталог может быть задан снаружи.
    func resetAll() {
        Task {
            await connection.disconnect()
            let fm = FileManager.default
            for name in ["servers.json", "routing.json", "settings.json", "client-id", "logs", "core-state"] {
                try? fm.removeItem(at: store.directory.appendingPathComponent(name))
            }
            readOnlyFiles = []
            loadError = nil
            servers = ServersFile()
            routing = RoutingFile.initial()
            settings = AppSettings()
            logs.clear()
            selectedServerId = nil
            section = .home
        }
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
