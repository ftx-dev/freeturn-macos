import CryptoKit
import Foundation

public struct AppVersion: Comparable, Sendable {
    let parts: [Int]

    public init(_ text: String) {
        var raw = text.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("v") { raw.removeFirst() }
        parts = raw.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    private func padded(_ n: Int) -> [Int] { parts + Array(repeating: 0, count: max(0, n - parts.count)) }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        return a.padded(n) == b.padded(n)
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        return a.padded(n).lexicographicallyPrecedes(b.padded(n))
    }
}

public struct AvailableUpdate: Equatable, Sendable {
    public var version: String
    public var dmgURL: URL
    public var checksumsURL: URL?
    public var pageURL: URL?
    public var notes: String

    public init(version: String, dmgURL: URL, checksumsURL: URL?, pageURL: URL?, notes: String) {
        self.version = version
        self.dmgURL = dmgURL
        self.checksumsURL = checksumsURL
        self.pageURL = pageURL
        self.notes = notes
    }
}

/// Обновления из GitHub Releases. DMG собирается под каждую архитектуру отдельно (make dmg),
/// поэтому берётся файл строго своей: FreeTurn-<версия>-<arm64|x86_64>.dmg.
public enum UpdateCheck {
    public static let repository = "huhhuh78787878-collab/freeturn-macos"
    public static var latestURL: URL { URL(string: "https://api.github.com/repos/\(repository)/releases/latest")! }

    /// Архитектура, под которую собран этот бинарник (а не машины: под Rosetta они расходятся).
    public static var currentArch: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            var name: String
            var browser_download_url: URL
        }
        var tag_name: String
        var draft: Bool
        var prerelease: Bool
        var html_url: String?
        var body: String?
        var assets: [Asset]
    }

    public static func available(from json: Data, current: String, arch: String) throws -> AvailableUpdate? {
        let release = try JSONDecoder().decode(Release.self, from: json)
        guard !release.draft, !release.prerelease, AppVersion(release.tag_name) > AppVersion(current) else { return nil }
        func asset(where match: (String) -> Bool) -> URL? {
            release.assets.first { match($0.name) && isGitHub($0.browser_download_url) }?.browser_download_url
        }
        guard let dmg = asset(where: { $0.hasPrefix("FreeTurn-") && $0.hasSuffix("-\(arch).dmg") }) else { return nil }
        var version = release.tag_name
        if version.hasPrefix("v") { version.removeFirst() }
        return AvailableUpdate(version: version, dmgURL: dmg, checksumsURL: asset { $0 == "SHA256SUMS.txt" },
                               pageURL: release.html_url.flatMap(URL.init(string:)), notes: release.body ?? "")
    }

    static func isGitHub(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }

    /// Строка «<sha256>  <имя файла>» из SHA256SUMS.txt.
    public static func checksum(for name: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count == 2, fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == name {
                return fields[0].lowercased()
            }
        }
        return nil
    }

    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
