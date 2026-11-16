import Foundation

public enum StoreError: Error, Equatable {
    /// Файл есть, но не читается как JSON нужной формы. Файл не трогаем.
    case corrupt(String)
}

/// JSON-файлы приложения в одном каталоге. В них лежат секреты, поэтому 0600.
public final class Store: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FreeTurn")
    }

    public func load<T: Decodable>(_ type: T.Type, from name: String, default fallback: T) throws -> T {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            throw StoreError.corrupt(name)
        }
    }

    public func save<T: Encodable>(_ value: T, to name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(encoder.encode(value), to: name)
    }

    public func ownClientId() throws -> String {
        let url = directory.appendingPathComponent("client-id")
        if let saved = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           saved.count == 32, saved.allSatisfy(\.isHexDigit) {
            return saved
        }
        let id = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        try write(Data(id.utf8), to: "client-id")
        return id
    }

    /// Client ID из резервной копии: без него сервер не пустит восстановленные профили (allowlist).
    public func setOwnClientId(_ id: String) throws {
        guard id.count == 32, id.allSatisfy(\.isHexDigit) else { throw StoreError.corrupt("client-id") }
        try write(Data(id.lowercased().utf8), to: "client-id")
    }

    /// Запись через временный файл и rename: обрыв посреди записи не портит прежний файл.
    private func write(_ data: Data, to name: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(name)
        let tmp = directory.appendingPathComponent(name + ".tmp")
        guard fm.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if rename(tmp.path, url.path) != 0 {
            try? fm.removeItem(at: tmp)
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
