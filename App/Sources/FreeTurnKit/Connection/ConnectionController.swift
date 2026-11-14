import Foundation
import Observation

/// Почему подключение не состоялось или оборвалось. Текст для человека даёт интерфейс.
public enum ConnectionFailure: Equatable, Sendable {
    case noAddress, noCallLink, noWireGuard, badWireGuard, invalidRule, noNetwork
    case daemonNotInstalled, daemonVersionMismatch, daemonBusy
    case core(String)
    case engine(String)
}

public enum ConnectionState: Equatable, Sendable {
    case off
    case starting
    case connecting(streams: Int, total: Int)
    case captcha
    case connected(streams: Int, total: Int)
    case failed(ConnectionFailure)
    case stopping

    public var isActive: Bool {
        switch self {
        case .off, .failed: false
        default: true
        }
    }
}

/// Ведёт одно подключение: служба -> ядро -> (после первого connected) движок.
/// До первого connected системная сеть не трогается: капча и подбор реле идут без туннеля.
@MainActor @Observable
public final class ConnectionController {
    public private(set) var state: ConnectionState = .off
    public private(set) var stats = TrafficStats()
    public private(set) var connectedSince: Date?
    public private(set) var captcha: CaptchaRequest?
    public private(set) var coreVersion = ""
    /// Эквивалентная CLI-команда ядра - для экрана отладки.
    public private(set) var launchArgs = ""
    public private(set) var activeServerId: String?

    @ObservationIgnored public var onLog: ((LogLine) -> Void)?

    @ObservationIgnored private let makeCore: () -> CoreControlling
    @ObservationIgnored private let makeEngine: () -> EngineControlling
    @ObservationIgnored private let network: NetworkWatching
    @ObservationIgnored private let portPicker: () throws -> Int

    @ObservationIgnored private var core: CoreControlling?
    @ObservationIgnored private var engine: EngineControlling?
    @ObservationIgnored private var engineConfig = ""
    @ObservationIgnored private var engineUp = false
    @ObservationIgnored private var lastNetwork: NetworkSnapshot?
    @ObservationIgnored private var networkLost = false
    /// Номер сессии: события прошлого ядра не должны оживлять новое подключение.
    @ObservationIgnored private var session = 0

    public init(core: @escaping () -> CoreControlling, engine: @escaping () -> EngineControlling,
                network: NetworkWatching, portPicker: @escaping () throws -> Int) {
        makeCore = core
        makeEngine = engine
        self.network = network
        self.portPicker = portPicker
    }

    public func connect(server: Server, profile: RoutingProfile, settings: AppSettings, ownClientId: String) async {
        guard !state.isActive else { return }
        let client = server.client
        guard !client.serverAddress.trimmingCharacters(in: .whitespaces).isEmpty else { return fail(.noAddress) }
        if client.provider == Provider.relay,
           client.callLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return fail(.noCallLink) }
        guard client.wireGuardActive else { return fail(.noWireGuard) }
        guard let wg = try? WGConfig.parse(client.wireGuardConfig) else { return fail(.badWireGuard) }
        guard let net = network.current() else { return fail(.noNetwork) }

        let port: Int
        let builtEngineConfig: String
        do {
            port = try portPicker()
            builtEngineConfig = try EngineConfig.build(
                wg: wg, corePort: port, profile: profile,
                settings: EngineSettings(stack: settings.tunStack, debug: client.debugMode))
        } catch is EngineConfigError {
            return fail(.invalidRule)
        } catch {
            return fail(.core("\(error)"))
        }

        session += 1
        let mySession = session
        state = .starting
        activeServerId = server.id

        let engine = makeEngine()
        do {
            let status = try await engine.status()
            guard status.version == DaemonProtocol.version else { throw DaemonError.versionMismatch(status.version) }
        } catch {
            engine.close()
            guard mySession == session else { return }
            switch error as? DaemonError {
            case .notInstalled: return fail(.daemonNotInstalled)
            case .versionMismatch: return fail(.daemonVersionMismatch)
            case .busy: return fail(.daemonBusy)
            case let .failed(message): return fail(.engine(message))
            case nil: return fail(.engine("\(error)"))
            }
        }
        // Пока ждали службу, пользователь мог нажать «отключить».
        guard mySession == session, state == .starting else { engine.close(); return }

        engine.onEvent = { [weak self] event in
            Task { @MainActor in
                guard let self, self.session == mySession else { return }
                await self.handle(engineEvent: event)
            }
        }
        let core = makeCore()
        core.onEvent = { [weak self] event in
            Task { @MainActor in
                guard let self, self.session == mySession else { return }
                await self.handle(coreEvent: event)
            }
        }
        self.engine = engine
        self.core = core
        engineConfig = builtEngineConfig
        engineUp = false
        lastNetwork = net
        networkLost = false

        do {
            try core.launch()
        } catch {
            return await teardown(.core("\(error)"))
        }
        let coreConfig = CoreConfig.build(server: server, listenPort: port, ownClientId: ownClientId,
                                          systemDNS: net.dns, advancedCaptcha: settings.advancedCaptcha)
        core.send(.args(config: coreConfig))
        core.send(.start(config: coreConfig, ifIndex: net.ifIndex))

        network.onChange = { [weak self] snapshot in self?.networkChanged(snapshot) }
        network.start()
    }

    public func disconnect() async {
        guard state.isActive, state != .stopping else { return }
        await teardown(nil)
    }

    func handle(coreEvent event: CoreEvent) async {
        guard state.isActive, state != .stopping else { return }
        switch event {
        case let .hello(version):
            coreVersion = version
        case let .args(args):
            launchArgs = args
        case let .log(level, msg, date):
            onLog?(LogLine(date: date, level: level, source: .core, text: msg))
        case let .stats(newStats):
            stats = newStats
        case let .captcha(url, manual):
            captcha = url.isEmpty ? nil : CaptchaRequest(url: url, manual: manual)
        case let .error(cmd, err):
            if cmd == "start" { await teardown(.core(err)) }
            else { onLog?(LogLine(level: .error, source: .core, text: "\(cmd): \(err)")) }
        case .exited:
            await teardown(.core("процесс ядра завершился"))
        case let .state(phase, streams, total, err):
            switch phase {
            case .connecting:
                state = .connecting(streams: streams, total: total)
            case .captcha:
                state = .captcha
            case .error:
                await teardown(.core(err))
            case .idle:
                // Ядро остановилось не по нашей команде.
                await teardown(.core(err.isEmpty ? "ядро остановилось" : err))
            case .connected:
                if !engineUp {
                    engineUp = true
                    let mySession = session
                    do {
                        try await engine?.start(config: engineConfig)
                    } catch {
                        guard mySession == session else { return }
                        let message: String
                        if case let .failed(text)? = error as? DaemonError { message = text } else { message = "\(error)" }
                        return await teardown(.engine(message))
                    }
                    guard mySession == session, state.isActive, state != .stopping else { return }
                    connectedSince = Date()
                }
                state = .connected(streams: streams, total: total)
            }
        }
    }

    func handle(engineEvent event: EngineEvent) async {
        guard state.isActive, state != .stopping else { return }
        switch event {
        case let .log(line):
            onLog?(LogLine(level: .info, source: .engine, text: line))
        case let .exited(_, tail):
            await teardown(.engine(tail))
        }
    }

    func networkChanged(_ snapshot: NetworkSnapshot?) {
        guard state.isActive, state != .stopping, let core else { return }
        guard let snapshot else {
            // Сети нет: привязывать сокеты не к чему. Запоминаем обрыв и ждём.
            networkLost = true
            return
        }
        guard networkLost || snapshot != lastNetwork else { return }
        networkLost = false
        lastNetwork = snapshot
        onLog?(LogLine(level: .info, source: .app, text: "Смена сети: \(snapshot.ifName) - переподключение"))
        core.send(.reconnect(ifIndex: snapshot.ifIndex, dns: snapshot.dns))
    }

    /// Короткий сон аллокации реле переживают; после долгого ядро надо разбудить сразу.
    public func systemDidWake(sleptSeconds: TimeInterval) {
        guard state.isActive, state != .stopping, sleptSeconds >= 60 else { return }
        onLog?(LogLine(level: .info, source: .app, text: "Пробуждение после сна \(Int(sleptSeconds)) с - будим ядро"))
        core?.send(.wake)
    }

    private func fail(_ failure: ConnectionFailure) {
        state = .failed(failure)
    }

    /// Сворачивает всё. Сначала движок - чтобы система не осталась с туннелем в мёртвый порт.
    private func teardown(_ failure: ConnectionFailure?) async {
        state = .stopping
        session += 1
        network.stop()
        network.onChange = nil
        let engine = self.engine
        let core = self.core
        self.engine = nil
        self.core = nil
        await engine?.stop()
        engine?.close()
        core?.send(.stop)
        core?.terminate()
        captcha = nil
        connectedSince = nil
        stats = TrafficStats()
        engineUp = false
        activeServerId = nil
        if case let .core(message)? = failure {
            onLog?(LogLine(level: .error, source: .app, text: "Подключение остановлено: \(message)"))
        }
        state = failure.map { .failed($0) } ?? .off
    }
}
