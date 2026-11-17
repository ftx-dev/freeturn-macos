import Foundation

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

    // Сохраняется отдельно от настроек приложения (UserDefaults), чтобы не трогать их формат.
    private static let defaultsKey = "socks5Client"

    public static func load(_ defaults: UserDefaults = .standard) -> Socks5ClientConfig {
        if let data = defaults.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(Socks5ClientConfig.self, from: data) {
            return saved
        }
        return Socks5ClientConfig()
    }

    public func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

/// Проверка, что по адресу отвечает SOCKS5 (приветствие RFC 1928), - до запуска туннеля.
public enum Socks5Probe {
    /// nil - прокси отвечает; иначе причина. Блокирующий: звать не с главного потока.
    public static func check(_ config: Socks5ClientConfig, timeout: Int = 4) -> String? {
        let host = config.host.trimmingCharacters(in: .whitespaces)
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(config.port), &hints, &info) == 0, let first = info else {
            return "SOCKS5 \(config.address): адрес не найден"
        }
        defer { freeaddrinfo(info) }
        let fd = socket(first.pointee.ai_family, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return "SOCKS5 \(config.address): нет сокета" }
        defer { close(fd) }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard connect(fd, first.pointee.ai_addr, first.pointee.ai_addrlen) == 0 else {
            return "SOCKS5 недоступен по адресу \(config.address)"
        }
        let greeting: [UInt8] = config.user.isEmpty ? [5, 1, 0] : [5, 2, 0, 2]
        guard send(fd, greeting, greeting.count, 0) == greeting.count else {
            return "SOCKS5 недоступен по адресу \(config.address)"
        }
        var reply = [UInt8](repeating: 0, count: 2)
        let got = recv(fd, &reply, 2, MSG_WAITALL)
        if got < 2 || reply[0] != 5 { return "по адресу \(config.address) SOCKS5 не ответил" }
        if reply[1] == 0xFF { return "SOCKS5 \(config.address) не принял логин/пароль" }
        return nil
    }
}
