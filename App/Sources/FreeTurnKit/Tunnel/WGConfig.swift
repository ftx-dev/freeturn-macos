import Foundation

public enum WGConfigError: Error, Equatable {
    case missingInterface, missingPrivateKey, missingAddress, missingPeer
    case missingPublicKey(peer: Int)
}

/// Конфиг wg-quick. MTU и Endpoint читаются и отбрасываются: MTU - константа туннеля,
/// а Endpoint заменяется локальным портом ядра.
public struct WGConfig: Equatable, Sendable {
    public struct Peer: Equatable, Sendable {
        public var publicKey = ""
        public var presharedKey: String?
        public var allowedIPs: [String] = []
        public var persistentKeepalive: Int?
    }

    public var privateKey = ""
    public var addresses: [String] = []
    public var dns: [String] = []
    /// Параметры AmneziaWG из [Interface], ключи в нижнем регистре.
    public var amnezia: [String: String] = [:]
    public var peers: [Peer] = []

    public var isAmnezia: Bool { !amnezia.isEmpty }

    /// Зеркало amnezia-ключей парсера ядра (internal/tunnel/wgconf).
    static let amneziaKeys: Set<String> = [
        "jc", "jmin", "jmax", "s1", "s2", "s3", "s4", "h1", "h2", "h3", "h4",
        "i1", "i2", "i3", "i4", "i5", "headerprotectionkey", "contentpaddingaddition",
        "rekeyaftertime", "rekeytimeout", "rejectaftertime", "keepalivetimeout",
        "maxhandshakeattempts", "randomtrailers", "disablecookies",
    ]

    public static func parse(_ text: String) throws -> WGConfig {
        enum Section { case none, interface, peer, other }
        var config = WGConfig()
        var section = Section.none
        var sawInterface = false

        for rawLine in text.split(whereSeparator: \.isNewline) {
            // Как в ядре: комментарий начинается с первого # или ; в строке.
            let line = rawLine.prefix { $0 != "#" && $0 != ";" }.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") {
                switch line.lowercased() {
                case "[interface]": section = .interface; sawInterface = true
                case "[peer]": section = .peer; config.peers.append(Peer())
                default: section = .other
                }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            switch section {
            case .interface:
                switch key {
                case "privatekey": config.privateKey = value
                case "address": config.addresses += list(value)
                case "dns": config.dns += list(value)
                default: if amneziaKeys.contains(key) { config.amnezia[key] = value }
                }
            case .peer:
                let i = config.peers.count - 1
                switch key {
                case "publickey": config.peers[i].publicKey = value
                case "presharedkey": config.peers[i].presharedKey = value
                case "allowedips": config.peers[i].allowedIPs += list(value)
                case "persistentkeepalive": config.peers[i].persistentKeepalive = Int(value)
                default: break
                }
            case .none, .other:
                break
            }
        }

        guard sawInterface else { throw WGConfigError.missingInterface }
        guard !config.privateKey.isEmpty else { throw WGConfigError.missingPrivateKey }
        guard !config.addresses.isEmpty else { throw WGConfigError.missingAddress }
        guard !config.peers.isEmpty else { throw WGConfigError.missingPeer }
        if let bad = config.peers.firstIndex(where: { $0.publicKey.isEmpty }) {
            throw WGConfigError.missingPublicKey(peer: bad)
        }
        return config
    }

    private static func list(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
