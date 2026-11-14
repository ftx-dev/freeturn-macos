import Foundation

public enum LinkError: Error, Equatable {
    case invalidScheme, emptyPayload, badEncoding, unsupportedVersion, missingProvider, missingPeer
}

/// Share-ссылка `freeturn://base64url(JSON)`, формат ядра (docs/uri.md) и Android-клиента.
public struct FreeturnLink: Equatable, Sendable {
    public var provider = ""
    public var peer = ""
    public var transport = ""
    public var mode = ""
    public var bond = false
    public var obfProfile = ""
    public var obfKey = ""
    public var obfTimingMs = 0
    public var n = 0
    public var streamsPerCred = 0
    public var clientId = ""
    public var dnsMode = ""
    public var dnsServers = ""
    public var manualCaptcha = false
    public var name = ""
    /// Ссылка на звонок владельца - опционально.
    public var callLink = ""
    public var wgConf = ""

    public static let scheme = "freeturn://"
    public static let version = 1

    public static func looksLikeLink(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(scheme)
    }

    public static func parse(_ raw: String) throws -> FreeturnLink {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeLink(trimmed) else { throw LinkError.invalidScheme }
        var payload = String(trimmed.dropFirst(scheme.count))
        while payload.hasSuffix("=") { payload.removeLast() }
        guard !payload.isEmpty else { throw LinkError.emptyPayload }

        var b64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw LinkError.badEncoding }

        guard o["v"] as? Int == version else { throw LinkError.unsupportedVersion }
        func str(_ key: String) -> String { o[key] as? String ?? "" }
        func int(_ key: String) -> Int { o[key] as? Int ?? 0 }
        func bool(_ key: String) -> Bool { o[key] as? Bool ?? false }

        var link = FreeturnLink()
        link.provider = str("provider")
        guard !link.provider.isEmpty else { throw LinkError.missingProvider }
        link.peer = str("peer")
        guard !link.peer.isEmpty else { throw LinkError.missingPeer }
        link.transport = str("transport")
        link.mode = str("mode")
        link.bond = bool("bond")
        link.obfProfile = str("obf")
        link.obfKey = str("key")
        link.obfTimingMs = int("timing")
        link.n = int("n")
        link.streamsPerCred = int("spc")
        link.clientId = str("cid")
        link.dnsMode = str("dns")
        link.dnsServers = str("dnss")
        link.manualCaptcha = bool("mcap")
        link.name = str("name")
        link.callLink = str("vk")
        link.wgConf = str("wg")
        return link
    }
}
