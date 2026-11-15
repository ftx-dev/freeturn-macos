import Foundation
import Testing
@testable import FreeTurnKit

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let coreBinary = repoRoot.appendingPathComponent("build/freeturn-core")
private let daemonBinary = repoRoot.appendingPathComponent("build/freeturnd")
private let fakeEngine = repoRoot.appendingPathComponent("helper/internal/daemon/testdata/fake-engine.sh")

@MainActor private func waitUntil(_ timeout: TimeInterval = 6, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

/// Настоящий процесс ядра (`make helper`): протокол, события и выход по закрытию stdin.
@MainActor @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: coreBinary.path)))
func coreProcessSpeaksProtocol() async throws {
    let core = CoreProcess(binary: coreBinary, stateDir: makeTempDir())
    var events: [CoreEvent] = []
    core.onEvent = { events.append($0) }
    try core.launch()
    #expect(await waitUntil { events.contains(.hello(version: AppInfo.coreVersion)) })

    let fixture = try String(contentsOf: repoRoot.appendingPathComponent("helper/internal/bridge/testdata/core-config-direct.json"), encoding: .utf8)
    core.send(.args(config: fixture))
    #expect(await waitUntil { events.contains { if case let .args(a) = $0 { return a.contains("-provider direct") }; return false } })

    core.send(.start(config: "{}", ifIndex: 0))
    #expect(await waitUntil { events.contains { if case .error(cmd: "start", _) = $0 { return true }; return false } })

    core.terminate()
    #expect(await waitUntil { events.contains(.exited) })
    // После выхода процесса запись не должна ронять приложение (SIGPIPE).
    core.send(.wake)
}

@MainActor @Test func coreProcessMissingBinaryThrows() {
    let core = CoreProcess(binary: URL(fileURLWithPath: "/nonexistent/freeturn-core"), stateDir: makeTempDir())
    #expect(throws: (any Error).self) { try core.launch() }
}

@MainActor @Test func daemonClientWithoutSocketIsNotInstalled() async {
    let client = DaemonClient(socketPath: "/tmp/ft-no-such-socket-\(UUID().uuidString)")
    await #expect(throws: DaemonError.notInstalled) { try await client.status() }
}

/// Настоящая служба (`make helper`) с подставным движком: протокол сокета целиком.
@MainActor @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: daemonBinary.path)))
func daemonClientTalksToRealDaemon() async throws {
    // Короткий путь: длина пути unix-сокета ограничена.
    let dir = URL(fileURLWithPath: "/tmp/ftd\(UInt32.random(in: 0...999_999))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let socket = dir.appendingPathComponent("d.sock").path

    let daemon = Process()
    daemon.executableURL = daemonBinary
    daemon.arguments = ["-socket", socket, "-owner-uid", "\(getuid())", "-engine", fakeEngine.path,
                        "-state-dir", dir.appendingPathComponent("state").path]
    try daemon.run()
    defer { daemon.terminate() }
    #expect(await waitUntil { FileManager.default.fileExists(atPath: socket) })

    let client = DaemonClient(socketPath: socket)
    var events: [EngineEvent] = []
    client.onEvent = { events.append($0) }
    #expect(try await client.status() == DaemonStatus(running: false, version: DaemonProtocol.version))

    let config = try EngineConfig.build(wg: WGConfig.parse(plainWG), corePort: 41000,
                                        profile: Presets.russiaDirect, settings: EngineSettings())
    try await client.start(config: config)
    #expect(try await client.status().running)
    #expect(await waitUntil { events.contains { if case let .log(l) = $0 { return l.contains("sing-box started") }; return false } })

    // Второй клиент при живом первом получает отказ.
    let second = DaemonClient(socketPath: socket)
    await #expect(throws: DaemonError.busy) { try await second.status() }
    second.close()

    await client.stop()
    #expect(try await !client.status().running)

    await #expect(throws: DaemonError.self) { try await client.start(config: #"{"experimental":{}}"#) }
    client.close()
}

/// Сервер, который на каждое подключение сразу отвечает «busy» и закрывает соединение -
/// так служба встречает второго клиента.
private func busyServer(at path: String) -> Int32 {
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: path.utf8) }
    _ = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    listen(fd, 64)
    Thread.detachNewThread {
        let reply = Array(#"{"ok":false,"err":"busy"}"#.utf8) + [0x0A]
        while true {
            let conn = accept(fd, nil, nil)
            guard conn >= 0 else { return }
            _ = write(conn, reply, reply.count)
            close(conn)
        }
    }
    return fd
}

// Ответ «busy» и закрытие соединения приходят почти одновременно с нашим запросом:
// отказ службы не должен превращаться в «соединение закрыто».
@MainActor @Test func busyReplySurvivesImmediateClose() async {
    let path = "/tmp/ftb\(UInt32.random(in: 0...999_999)).sock"
    let server = busyServer(at: path)
    defer { close(server); unlink(path) }
    var other: [String] = []
    for _ in 0..<300 {
        let client = DaemonClient(socketPath: path)
        do {
            _ = try await client.status()
            other.append("no error")
        } catch DaemonError.busy {
        } catch {
            other.append("\(error)")
        }
        client.close()
    }
    #expect(other.isEmpty, "вместо busy: \(Set(other)), \(other.count) из 300")
}
