import Foundation
import SystemConfiguration

/// SOCKS5-клиент (экспериментально): весь трафик Mac - в чужой SOCKS5, например в SOCKS5 Hotspot
/// телефона с FreeTurn/FreeTurnX, к чьему Wi-Fi подключён Mac. Ядро FreeTurn не участвует:
/// служба запускает движок с этим конфигом (tun -> socks).
public struct Socks5ClientConfig: Equatable, Sendable, Codable {
    public var host: String
    public var port: Int
    public var user: String
    public var password: String

    public static let defaultPort = 1080

    public init(host: String = "", port: Int = Socks5ClientConfig.defaultPort, user: String = "", password: String = "") {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
    }

    public var isValid: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty && (1...65535).contains(port) }
    public var address: String { "\(host):\(port)" }

    /// Конфиг движка (формат sing-box 1.12). DNS идёт через прокси по TCP - так он работает,
    /// даже если на раздающем телефоне выключен UDP. Локальная сеть - напрямую.
    public func engineConfig(mtu: Int, stack: String = "mixed", debug: Bool = false) throws -> String {
        var socks: [String: Any] = [
            "type": "socks", "tag": "socks", "version": "5",
            "server": host.trimmingCharacters(in: .whitespaces), "server_port": port,
        ]
        if !user.isEmpty {
            socks["username"] = user
            socks["password"] = password
        }
        let config: [String: Any] = [
            "log": ["level": debug ? "debug" : "info"],
            "dns": [
                "servers": [
                    ["type": "tcp", "tag": "proxy-dns", "server": "1.1.1.1", "detour": "socks"],
                    ["type": "local", "tag": "local-dns"],
                ],
                "final": "proxy-dns",
                "strategy": "ipv4_only",
            ],
            "inbounds": [[
                "type": "tun", "tag": "tun-in",
                "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                "mtu": mtu, "auto_route": true, "stack": stack,
            ]],
            "outbounds": [socks, ["type": "direct", "tag": "direct"]],
            "route": [
                "auto_detect_interface": true,
                "default_domain_resolver": "local-dns",
                "final": "socks",
                "rules": [
                    ["action": "sniff"],
                    ["protocol": "dns", "action": "hijack-dns"],
                    ["ip_is_private": true, "outbound": "direct"],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Шлюз основной сети: в сети точки доступа это и есть раздающий телефон.
    public static func defaultGateway() -> String? {
        let store = SCDynamicStoreCreate(nil, "FreeTurn" as CFString, nil, nil)
        let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        return ipv4?["Router"] as? String
    }

    // Сохраняется отдельно от настроек приложения (UserDefaults), чтобы не трогать их формат.
    private static let defaultsKey = "socks5Client"

    public static func load(_ defaults: UserDefaults = .standard) -> Socks5ClientConfig {
        if let data = defaults.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(Socks5ClientConfig.self, from: data) {
            return saved
        }
        return Socks5ClientConfig(host: defaultGateway() ?? "")
    }

    public func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
