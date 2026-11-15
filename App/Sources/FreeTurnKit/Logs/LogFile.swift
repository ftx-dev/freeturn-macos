import Foundation

/// Лог сессии на диске: экранный лог чистится при каждом подключении, а разбирать сбой
/// приходится уже после перезапуска. Два файла по maxBytes: текущий и предыдущий.
public final class LogFile: @unchecked Sendable {
    private let directory: URL
    private let maxBytes: Int
    private let lock = NSLock()

    private var current: URL { directory.appendingPathComponent("session.log") }
    private var previous: URL { directory.appendingPathComponent("session.1.log") }

    public init(directory: URL, maxBytes: Int = 1_000_000) {
        self.directory = directory
        self.maxBytes = maxBytes
    }

    public func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        let data = Data((line + "\n").utf8)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let size = (try? fm.attributesOfItem(atPath: current.path)[.size] as? NSNumber)?.intValue ?? 0
        if size > 0, size + data.count > maxBytes {
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: current, to: previous)
        }
        if !fm.fileExists(atPath: current.path) {
            fm.createFile(atPath: current.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: current) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    public func export(to target: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        let old = (try? Data(contentsOf: previous)) ?? Data()
        let new = (try? Data(contentsOf: current)) ?? Data()
        try (old + new).write(to: target)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: current)
        try? FileManager.default.removeItem(at: previous)
    }
}
