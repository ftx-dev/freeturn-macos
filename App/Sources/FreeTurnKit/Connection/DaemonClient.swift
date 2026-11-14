import Foundation

/// Клиент службы freeturnd (unix-сокет, строки JSON).
/// Пока соединение открыто, служба держит движок; закрытие соединения снимает туннель.
@MainActor
public final class DaemonClient: EngineControlling {
    public var onEvent: (@MainActor (EngineEvent) -> Void)?

    private let socketPath: String
    private var connection: Connection?

    public init(socketPath: String = DaemonProtocol.socketPath) {
        self.socketPath = socketPath
    }

    public func status() async throws -> DaemonStatus {
        let reply = try await request(["cmd": "status"])
        return DaemonStatus(running: reply.running, version: reply.version)
    }

    public func start(config: String) async throws {
        _ = try await request(["cmd": "start", "config": config])
    }

    public func stop() async {
        guard connection != nil else { return }
        _ = try? await request(["cmd": "stop"])
    }

    public func close() {
        connection?.close()
        connection = nil
    }

    private func request(_ body: [String: String]) async throws -> Reply {
        let connection = try connected()
        let line = try JSONSerialization.data(withJSONObject: body) + Data("\n".utf8)
        let reply = try await connection.send(line)
        guard reply.ok else {
            switch reply.err {
            case "busy": throw DaemonError.busy
            default: throw DaemonError.failed(reply.err)
            }
        }
        return reply
    }

    private func connected() throws -> Connection {
        if let connection, connection.isOpen { return connection }
        let fresh = try Connection(path: socketPath) { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onEvent?(event) }
            }
        }
        connection = fresh
        return fresh
    }
}

private struct Reply: Sendable {
    var ok = false
    var err = ""
    var running = false
    var version = ""
}

/// Сокет и поток чтения. Ответы приходят в порядке запросов: служба обрабатывает их по одному.
private final class Connection: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Reply, Error>] = []
    /// Ответ без запроса: служба сама говорит «busy» или «forbidden» при подключении.
    private var unsolicited: Reply?
    private var open = true

    var isOpen: Bool { lock.withLock { open } }

    init(path: String, onEvent: @escaping @Sendable (EngineEvent) -> Void) throws {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else { throw DaemonError.failed("слишком длинный путь сокета") }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: path.utf8)
        }

        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DaemonError.failed("socket: \(String(cString: strerror(errno)))") }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let code = errno
            Darwin.close(fd)
            // Нет сокета, никто не слушает или сокет чужого пользователя - службу надо (пере)ставить.
            if [ENOENT, ECONNREFUSED, EACCES, EPERM].contains(code) { throw DaemonError.notInstalled }
            throw DaemonError.failed("connect: \(String(cString: strerror(code)))")
        }

        let readFD = fd
        Thread.detachNewThread { [weak self] in
            let splitter = LineSplitter()
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let n = read(readFD, &chunk, chunk.count)
                guard n > 0 else { break }
                for line in splitter.feed(Data(chunk[0..<n])) {
                    self?.receive(line: line, onEvent: onEvent)
                }
            }
            self?.finish()
        }
    }

    func send(_ line: Data) async throws -> Reply {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let early = unsolicited {
                unsolicited = nil
                lock.unlock()
                continuation.resume(returning: early)
                return
            }
            guard open else {
                lock.unlock()
                continuation.resume(throwing: DaemonError.failed("служба закрыла соединение"))
                return
            }
            waiting.append(continuation)
            lock.unlock()
            let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if written != line.count { finish() }
        }
    }

    private func receive(line: String, onEvent: (EngineEvent) -> Void) {
        guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
        if let ev = o["ev"] as? String {
            switch ev {
            case "log": onEvent(.log(o["line"] as? String ?? ""))
            case "exit": onEvent(.exited(code: o["code"] as? Int ?? 0, tail: o["tail"] as? String ?? ""))
            default: break
            }
            return
        }
        let reply = Reply(ok: o["ok"] as? Bool ?? false, err: o["err"] as? String ?? "",
                          running: o["running"] as? Bool ?? false, version: o["version"] as? String ?? "")
        lock.lock()
        if waiting.isEmpty {
            unsolicited = reply
            lock.unlock()
        } else {
            let continuation = waiting.removeFirst()
            lock.unlock()
            continuation.resume(returning: reply)
        }
    }

    /// Соединение кончилось: все, кто ждал ответа, получают ошибку.
    private func finish() {
        lock.lock()
        open = false
        let pending = waiting
        waiting = []
        lock.unlock()
        pending.forEach { $0.resume(throwing: DaemonError.failed("служба закрыла соединение")) }
    }

    func close() {
        shutdown(fd, SHUT_RDWR)
        finish()
    }

    deinit { Darwin.close(fd) }
}
