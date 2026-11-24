import Foundation

public struct TrafficStats: Equatable, Sendable {
    public var tx: Int64 = 0
    public var rx: Int64 = 0
    public var txRate: Int64 = 0
    public var rxRate: Int64 = 0

    public init(tx: Int64 = 0, rx: Int64 = 0, txRate: Int64 = 0, rxRate: Int64 = 0) {
        self.tx = tx
        self.rx = rx
        self.txRate = txRate
        self.rxRate = rxRate
    }
}

public enum LogLevel: String, Sendable, CaseIterable { case debug, info, warn, error }
public enum LogSource: String, Sendable, CaseIterable { case core, engine, app }

public struct LogLine: Identifiable, Equatable, Sendable {
    public struct RGB: Equatable, Sendable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8
    }

    public struct Segment: Equatable, Sendable {
        public internal(set) var text: String
        public let foreground: RGB?
        public let background: RGB?
    }

    public var id: Int
    public var date: Date
    public var level: LogLevel
    public var source: LogSource
    public private(set) var text: String
    public private(set) var segments: [Segment]?

    public init(id: Int = 0, date: Date = Date(), level: LogLevel, source: LogSource, text: String) {
        self.id = id
        self.date = date
        self.level = level
        self.source = source
        let segments = ANSIColors.decode(text)
        self.text = segments?.map(\.text).joined() ?? text
        self.segments = segments
    }

    public mutating func redactText(secrets: [String], maskAddresses: Bool = true) {
        let redacted = Redactor.redact(text, secrets: secrets, maskAddresses: maskAddresses)
        guard redacted != text else { return }
        text = redacted
        if let segments {
            let redactedSegments = segments.map {
                Segment(text: Redactor.redact($0.text, secrets: secrets, maskAddresses: maskAddresses),
                        foreground: $0.foreground, background: $0.background)
            }
            // Секрет может пересекать границы цвета. Тогда показываем результат редактирования всей строки.
            self.segments = redactedSegments.map(\.text).joined() == redacted ? redactedSegments : nil
        }
    }
}

public struct CaptchaRequest: Equatable, Sendable {
    public var url: String
    public var manual: Bool

    public init(url: String, manual: Bool) {
        self.url = url
        self.manual = manual
    }
}

public enum CorePhase: String, Sendable { case idle, connecting, connected, captcha, error }

/// События процесса freeturn-core (строки JSON в его stdout).
public enum CoreEvent: Equatable, Sendable {
    case hello(version: String)
    case state(phase: CorePhase, streams: Int, total: Int, err: String)
    case log(level: LogLevel, msg: String, date: Date)
    /// Пустой url - капчу убрать.
    case captcha(url: String, manual: Bool)
    case stats(TrafficStats)
    case args(String)
    case error(cmd: String, err: String)
    /// Процесс ядра завершился.
    case exited

    public static func decode(line: String) -> CoreEvent? {
        guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        func str(_ key: String) -> String { o[key] as? String ?? "" }
        func int(_ key: String) -> Int { o[key] as? Int ?? 0 }
        func int64(_ key: String) -> Int64 { (o[key] as? NSNumber)?.int64Value ?? 0 }

        switch str("ev") {
        case "hello":
            return .hello(version: str("version"))
        case "state":
            guard let phase = CorePhase(rawValue: str("state")) else { return nil }
            return .state(phase: phase, streams: int("streams"), total: int("total"), err: str("err"))
        case "log":
            return .log(level: LogLevel(rawValue: str("level")) ?? .info, msg: str("msg"),
                        date: Date(timeIntervalSince1970: Double(int64("ts")) / 1000))
        case "captcha":
            return .captcha(url: str("url"), manual: o["manual"] as? Bool ?? false)
        case "stats":
            return .stats(TrafficStats(tx: int64("tx"), rx: int64("rx"), txRate: int64("txRate"), rxRate: int64("rxRate")))
        case "args":
            return .args(str("args"))
        case "error":
            return .error(cmd: str("cmd"), err: str("err"))
        default:
            return nil
        }
    }
}

/// Команды процессу freeturn-core (строки JSON в его stdin).
public enum CoreCommand: Equatable, Sendable {
    case start(config: String, ifIndex: Int32, ifIndex6: Int32? = nil)
    case stop
    case reconnect(ifIndex: Int32, ifIndex6: Int32? = nil, dns: [String])
    case wake
    case args(config: String)

    public func encoded() -> String {
        var object: [String: Any]
        switch self {
        case let .start(config, ifIndex, ifIndex6):
            object = ["cmd": "start", "config": config, "ifIndex": Int(ifIndex)]
            object["ifIndex6"] = ifIndex6
        case .stop: object = ["cmd": "stop"]
        case let .reconnect(ifIndex, ifIndex6, dns):
            object = ["cmd": "reconnect", "ifIndex": Int(ifIndex), "dns": dns.joined(separator: ",")]
            object["ifIndex6"] = ifIndex6
        case .wake: object = ["cmd": "wake"]
        case let .args(config): object = ["cmd": "args", "config": config]
        }
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

public enum EngineEvent: Equatable, Sendable {
    case log(String)
    /// Движок умер сам: туннеля больше нет.
    case exited(code: Int, tail: String)
}

public struct DaemonStatus: Equatable, Sendable {
    public var running: Bool
    public var version: String

    public init(running: Bool, version: String) {
        self.running = running
        self.version = version
    }
}

public enum DaemonError: Error, Equatable, Sendable {
    case notInstalled
    case busy
    case versionMismatch(String)
    case failed(String)
}

public enum DaemonProtocol {
    /// Должна совпадать с daemon.ProtocolVersion в helper/internal/daemon/server.go.
    public static let version = "2"
    public static let socketPath = "/var/run/freeturnd.sock"
}

@MainActor public protocol CoreControlling: AnyObject {
    var onEvent: (@MainActor (CoreEvent) -> Void)? { get set }
    func launch() throws
    func send(_ command: CoreCommand)
    func terminate()
}

@MainActor public protocol EngineControlling: AnyObject {
    var onEvent: (@MainActor (EngineEvent) -> Void)? { get set }
    func status() async throws -> DaemonStatus
    func start(config: String) async throws
    func stop() async
    func close()
}

@MainActor public protocol NetworkWatching: AnyObject {
    /// nil - сети нет.
    var onChange: (@MainActor (NetworkSnapshot?) -> Void)? { get set }
    func current() -> NetworkSnapshot?
    func start()
    func stop()
}
