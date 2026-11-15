import Foundation
import Testing
@testable import FreeTurnKit

@MainActor final class CallLog { var calls: [String] = [] }

@MainActor final class FakeCore: CoreControlling {
    var onEvent: (@MainActor (CoreEvent) -> Void)?
    let log: CallLog
    var commands: [CoreCommand] = []
    var launched = false
    var terminated = false
    var launchError: Error?
    init(log: CallLog) { self.log = log }
    func launch() throws {
        if let launchError { throw launchError }
        launched = true
        log.calls.append("core.launch")
    }
    func send(_ command: CoreCommand) {
        commands.append(command)
        log.calls.append("core." + (command.encoded().contains(#""cmd":"stop""#) ? "stop" : "send"))
    }
    func terminate() { terminated = true; log.calls.append("core.terminate") }
}

@MainActor final class FakeEngine: EngineControlling {
    var onEvent: (@MainActor (EngineEvent) -> Void)?
    let log: CallLog
    var statusResult: Result<DaemonStatus, DaemonError> = .success(DaemonStatus(running: false, version: DaemonProtocol.version))
    var startError: DaemonError?
    var startedConfigs: [String] = []
    var stopped = false
    var closed = false
    init(log: CallLog) { self.log = log }
    func status() async throws -> DaemonStatus { try statusResult.get() }
    func start(config: String) async throws {
        log.calls.append("engine.start")
        if let startError { throw startError }
        startedConfigs.append(config)
    }
    func stop() async { stopped = true; log.calls.append("engine.stop") }
    func close() { closed = true; log.calls.append("engine.close") }
}

@MainActor final class FakeNetwork: NetworkWatching {
    var onChange: (@MainActor (NetworkSnapshot?) -> Void)?
    var snapshot: NetworkSnapshot? = NetworkSnapshot(ifName: "en0", ifIndex: 11, dns: ["192.168.1.1"])
    var started = false
    func current() -> NetworkSnapshot? { snapshot }
    func start() { started = true }
    func stop() { started = false }
}

@MainActor struct Rig {
    let log = CallLog()
    let core: FakeCore
    let engine: FakeEngine
    let network = FakeNetwork()
    let controller: ConnectionController
    var server: Server

    init() {
        let log = self.log
        let core = FakeCore(log: log)
        let engine = FakeEngine(log: log)
        self.core = core
        self.engine = engine
        controller = ConnectionController(core: { core }, engine: { engine }, network: network, portPicker: { 41000 })
        var s = Server(name: "S")
        s.client.serverAddress = "1.2.3.4:56000"
        s.client.callLink = "https://vk.ru/call/join/x"
        s.client.tunnelTransport = "wireguard"
        s.client.wireGuardConfig = plainWG
        server = s
    }

    func connect(profile: RoutingProfile = Presets.allViaVPN) async {
        await controller.connect(server: server, profile: profile, settings: AppSettings(), ownClientId: hex32)
    }

    func connected(streams: Int = 3) async {
        await controller.handle(coreEvent: .state(phase: .connected, streams: streams, total: 12, err: ""))
    }

    var startCommand: [String: Any]? {
        for case let .start(config, _) in core.commands {
            return try? JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any]
        }
        return nil
    }
}

@MainActor @Test func engineStartsOnlyAfterFirstConnected() async {
    let rig = Rig()
    await rig.connect()
    #expect(rig.core.launched)
    #expect(rig.engine.startedConfigs.isEmpty)
    #expect(rig.controller.state == .starting)
    await rig.controller.handle(coreEvent: .state(phase: .connecting, streams: 0, total: 12, err: ""))
    #expect(rig.controller.state == .connecting(streams: 0, total: 12))
    #expect(rig.engine.startedConfigs.isEmpty)
    await rig.connected()
    #expect(rig.engine.startedConfigs.count == 1)
    #expect(rig.controller.state == .connected(streams: 3, total: 12))
    // Повторные события connected движок заново не запускают.
    await rig.connected(streams: 5)
    #expect(rig.engine.startedConfigs.count == 1)
    #expect(rig.controller.state == .connected(streams: 5, total: 12))
}

@MainActor @Test func engineConfigTargetsPickedPort() async throws {
    let rig = Rig()
    await rig.connect()
    await rig.connected()
    let engineCfg = try JSONSerialization.jsonObject(with: Data(rig.engine.startedConfigs[0].utf8)) as! [String: Any]
    let peer = ((engineCfg["endpoints"] as! [[String: Any]])[0]["peers"] as! [[String: Any]])[0]
    #expect(peer["port"] as? Int == 41000)
    #expect((rig.startCommand?["proxy"] as? [String: Any])?["listen"] as? String == "127.0.0.1:41000")
    let ifIndexes = rig.core.commands.compactMap { command -> Int32? in
        if case let .start(_, ifIndex) = command { return ifIndex }
        return nil
    }
    #expect(ifIndexes == [11])
    #expect((rig.startCommand?["dns"] as? [String: Any])?["servers"] as? [String] == ["192.168.1.1"])
}

@MainActor @Test func disconnectStopsEngineThenCore() async {
    let rig = Rig()
    await rig.connect()
    await rig.connected()
    rig.log.calls.removeAll()
    await rig.controller.disconnect()
    #expect(rig.log.calls == ["engine.stop", "engine.close", "core.stop", "core.terminate"])
    #expect(rig.controller.state == .off)
    #expect(!rig.network.started)
}

@MainActor @Test func coreErrorTearsDownEverything() async {
    let rig = Rig()
    await rig.connect()
    await rig.connected()
    await rig.controller.handle(coreEvent: .state(phase: .error, streams: 0, total: 12, err: "boom"))
    #expect(rig.engine.stopped)
    #expect(rig.core.terminated)
    #expect(rig.controller.state == .failed(.core("boom")))
    #expect(rig.controller.connectedSince == nil)
}

@MainActor @Test func coreStartErrorFails() async {
    let rig = Rig()
    await rig.connect()
    await rig.controller.handle(coreEvent: .error(cmd: "start", err: "listen udp 127.0.0.1:41000: address already in use"))
    #expect(rig.controller.state == .failed(.core("listen udp 127.0.0.1:41000: address already in use")))
    #expect(rig.engine.startedConfigs.isEmpty)
    #expect(rig.core.terminated)
}

@MainActor @Test func coreProcessExitFails() async {
    let rig = Rig()
    await rig.connect()
    await rig.connected()
    await rig.controller.handle(coreEvent: .exited)
    #expect(rig.engine.stopped)
    guard case .failed(.core) = rig.controller.state else { Issue.record("state = \(rig.controller.state)"); return }
}

@MainActor @Test func engineExitTearsDownCore() async {
    let rig = Rig()
    await rig.connect()
    await rig.connected()
    await rig.controller.handle(engineEvent: .exited(code: 1, tail: "tun died"))
    #expect(rig.core.terminated)
    #expect(rig.controller.state == .failed(.engine("tun died")))
}

@MainActor @Test func engineStartFailureTearsDownCore() async {
    let rig = Rig()
    rig.engine.startError = .failed("engine exited with code 1: FATAL")
    await rig.connect()
    await rig.connected()
    #expect(rig.core.terminated)
    #expect(rig.controller.state == .failed(.engine("engine exited with code 1: FATAL")))
}

@MainActor @Test func daemonNotInstalledFailsBeforeCoreLaunch() async {
    let rig = Rig()
    rig.engine.statusResult = .failure(.notInstalled)
    await rig.connect()
    #expect(!rig.core.launched)
    #expect(rig.controller.state == .failed(.daemonNotInstalled))
}

@MainActor @Test func daemonVersionMismatchFails() async {
    let rig = Rig()
    rig.engine.statusResult = .success(DaemonStatus(running: false, version: "0"))
    await rig.connect()
    #expect(!rig.core.launched)
    #expect(rig.controller.state == .failed(.daemonVersionMismatch))
}

@MainActor @Test func captchaEventSurfaces() async {
    let rig = Rig()
    await rig.connect()
    await rig.controller.handle(coreEvent: .state(phase: .captcha, streams: 0, total: 12, err: ""))
    await rig.controller.handle(coreEvent: .captcha(url: "http://localhost:8765/x", manual: true))
    #expect(rig.controller.state == .captcha)
    #expect(rig.controller.captcha == CaptchaRequest(url: "http://localhost:8765/x", manual: true))
    await rig.controller.handle(coreEvent: .captcha(url: "", manual: false))
    #expect(rig.controller.captcha == nil)
}

@MainActor @Test func disconnectClearsCaptcha() async {
    let rig = Rig()
    await rig.connect()
    await rig.controller.handle(coreEvent: .captcha(url: "http://localhost:8765/x", manual: true))
    await rig.controller.disconnect()
    #expect(rig.controller.captcha == nil)
}

@MainActor @Test func networkChangeSendsReconnect() async {
    let rig = Rig()
    await rig.connect()
    await rig.connected()
    rig.core.commands.removeAll()
    rig.controller.networkChanged(NetworkSnapshot(ifName: "en5", ifIndex: 20, dns: ["10.0.0.1"]))
    #expect(rig.core.commands == [.reconnect(ifIndex: 20, dns: ["10.0.0.1"])])
}

// Сети нет: привязывать сокеты ядра не к чему, ждём её возвращения.
@MainActor @Test func networkLossThenReturn() async {
    let rig = Rig()
    await rig.connect()
    await rig.connected()
    rig.core.commands.removeAll()
    rig.controller.networkChanged(nil)
    #expect(rig.core.commands.isEmpty)
    #expect(rig.controller.state == .connected(streams: 3, total: 12))
    // Та же сеть вернулась: аллокации за время обрыва протухли, нужен reconnect.
    rig.controller.networkChanged(NetworkSnapshot(ifName: "en0", ifIndex: 11, dns: ["192.168.1.1"]))
    #expect(rig.core.commands == [.reconnect(ifIndex: 11, dns: ["192.168.1.1"])])
}

@MainActor @Test func sameNetworkNoReconnect() async {
    let rig = Rig()
    await rig.connect()
    rig.core.commands.removeAll()
    rig.controller.networkChanged(NetworkSnapshot(ifName: "en0", ifIndex: 11, dns: ["192.168.1.1"]))
    #expect(rig.core.commands.isEmpty)
}

@MainActor @Test func networkChangeIgnoredWhenOff() async {
    let rig = Rig()
    rig.controller.networkChanged(NetworkSnapshot(ifName: "en5", ifIndex: 20, dns: []))
    #expect(rig.core.commands.isEmpty)
}

@MainActor @Test func noNetworkAtConnectFails() async {
    let rig = Rig()
    rig.network.snapshot = nil
    await rig.connect()
    #expect(rig.controller.state == .failed(.noNetwork))
    #expect(!rig.core.launched)
}

@MainActor @Test func wakeAfterLongSleepOnly() async {
    let rig = Rig()
    await rig.connect()
    await rig.connected()
    rig.core.commands.removeAll()
    rig.controller.systemDidWake(sleptSeconds: 30)
    #expect(rig.core.commands.isEmpty)
    rig.controller.systemDidWake(sleptSeconds: 90)
    #expect(rig.core.commands == [.wake])
}

@MainActor @Test func serverWithoutWireGuardFails() async {
    var rig = Rig()
    rig.server.client.wireGuardConfig = ""
    await rig.connect()
    #expect(rig.controller.state == .failed(.noWireGuard))
    #expect(!rig.core.launched)
}

@MainActor @Test func brokenWireGuardFails() async {
    var rig = Rig()
    rig.server.client.wireGuardConfig = "[Interface]\nAddress = 10.0.0.2\n"
    await rig.connect()
    #expect(rig.controller.state == .failed(.badWireGuard))
}

@MainActor @Test func relayWithoutCallLinkFails() async {
    var rig = Rig()
    rig.server.client.callLink = "  "
    await rig.connect()
    #expect(rig.controller.state == .failed(.noCallLink))
    rig.server.client.provider = "direct"
    await rig.connect()
    #expect(rig.controller.state == .starting)
}

@MainActor @Test func invalidRuleFailsBeforeLaunch() async {
    let rig = Rig()
    let bad = RoutingProfile(name: "bad", defaultAction: .vpn, rules: [RoutingRule(kind: .cidr, value: "nope", action: .direct)])
    await rig.connect(profile: bad)
    #expect(rig.controller.state == .failed(.invalidRule))
    #expect(!rig.core.launched)
}

@MainActor @Test func statsAndUptime() async {
    let rig = Rig()
    await rig.connect()
    #expect(rig.controller.connectedSince == nil)
    await rig.connected()
    let since = rig.controller.connectedSince
    #expect(since != nil)
    await rig.controller.handle(coreEvent: .stats(TrafficStats(tx: 10, rx: 20, txRate: 1, rxRate: 2)))
    #expect(rig.controller.stats == TrafficStats(tx: 10, rx: 20, txRate: 1, rxRate: 2))
    // Переподключение ядра не сбрасывает время сессии.
    await rig.controller.handle(coreEvent: .state(phase: .connecting, streams: 0, total: 12, err: ""))
    await rig.connected()
    #expect(rig.controller.connectedSince == since)
    await rig.controller.disconnect()
    #expect(rig.controller.connectedSince == nil)
    #expect(rig.controller.stats == TrafficStats())
}

@MainActor @Test func logsAreForwarded() async {
    let rig = Rig()
    var lines: [LogLine] = []
    rig.controller.onLog = { lines.append($0) }
    await rig.connect()
    await rig.controller.handle(coreEvent: .log(level: .warn, msg: "hello", date: Date(timeIntervalSince1970: 5)))
    await rig.connected()
    await rig.controller.handle(engineEvent: .log("engine line"))
    #expect(lines.contains { $0.source == .core && $0.level == .warn && $0.text == "hello" })
    #expect(lines.contains { $0.source == .engine && $0.text == "engine line" })
}

@MainActor @Test func connectWhileActiveIsIgnored() async {
    let rig = Rig()
    await rig.connect()
    await rig.connect()
    #expect(rig.log.calls.filter { $0 == "core.launch" }.count == 1)
}

@MainActor @Test func captchaChangesNotify() async {
    let rig = Rig()
    var seen: [CaptchaRequest?] = []
    rig.controller.onCaptchaChange = { seen.append($0) }
    await rig.connect()
    await rig.controller.handle(coreEvent: .captcha(url: "http://localhost:8765/x", manual: true))
    await rig.controller.handle(coreEvent: .captcha(url: "", manual: false))
    await rig.controller.handle(coreEvent: .captcha(url: "http://localhost:8765/y", manual: false))
    await rig.controller.disconnect()
    #expect(seen == [CaptchaRequest(url: "http://localhost:8765/x", manual: true), nil,
                     CaptchaRequest(url: "http://localhost:8765/y", manual: false), nil])
}

// Команда запуска - главная строка при разборе сбоев: она должна быть в логе.
@MainActor @Test func launchCommandIsLogged() async {
    let rig = Rig()
    var lines: [LogLine] = []
    rig.controller.onLog = { lines.append($0) }
    await rig.connect()
    await rig.controller.handle(coreEvent: .args("-peer 1.2.3.4:56000 -provider vk"))
    #expect(lines.contains { $0.source == .app && $0.text == "Команда: -peer 1.2.3.4:56000 -provider vk" })
    #expect(rig.controller.launchArgs == "-peer 1.2.3.4:56000 -provider vk")
}

@MainActor @Test func stateChangesNotify() async {
    let rig = Rig()
    var seen: [ConnectionState] = []
    rig.controller.onStateChange = { seen.append($0) }
    await rig.connect()
    await rig.connected()
    await rig.connected(streams: 3)
    await rig.controller.disconnect()
    #expect(seen == [.starting, .connected(streams: 3, total: 12), .stopping, .off])
}
