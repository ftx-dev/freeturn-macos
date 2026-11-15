import Foundation

public struct EngineSettings: Equatable, Sendable {
    /// Стек TUN движка: system | gvisor | mixed.
    public var stack: String
    /// DNS для трафика через VPN; nil - первый DNS из конфига WG.
    public var vpnDNS: String?
    public var debug: Bool

    public init(stack: String = "mixed", vpnDNS: String? = nil, debug: Bool = false) {
        self.stack = stack
        self.vpnDNS = vpnDNS
        self.debug = debug
    }
}

public enum EngineConfigError: Error, Equatable {
    case invalidRule(id: String)
}

/// Конфиг движка (Amnezia Box, формат sing-box 1.12): tun + WG/AWG в локальный порт ядра + правила.
public enum EngineConfig {
    private static let awgInts: Set<String> = ["jc", "jmin", "jmax", "s1", "s2", "s3", "s4"]
    private static let awgBools = ["randomtrailers": "random_trailers", "disablecookies": "disable_cookies"]
    private static let awgRenamed = [
        "headerprotectionkey": "header_protection_key", "contentpaddingaddition": "content_padding_addition",
        "rekeyaftertime": "rekey_after_time", "rekeytimeout": "rekey_timeout",
        "rejectaftertime": "reject_after_time", "keepalivetimeout": "keepalive_timeout",
        "maxhandshakeattempts": "max_handshake_attempts",
    ]

    public static func build(wg: WGConfig, corePort: Int, profile: RoutingProfile,
                             settings: EngineSettings) throws -> String {
        let hasV6 = wg.addresses.contains { $0.contains(":") }
        let matchers = try profile.rules.filter(\.enabled).map { ($0, try matcher(for: $0)) }
        let viaVPN = profile.defaultAction != .direct

        var tun: [String: Any] = [
            "type": "tun", "tag": "tun-in",
            "address": ["172.19.0.1/30"] + (hasV6 ? ["fdfe:dcba:9876::1/126"] : []),
            "mtu": CoreConfig.tunnelMTU, "auto_route": true, "stack": settings.stack,
        ]
        // AllowedIPs без 0.0.0.0/0 - в туннель попадают только эти сети.
        let allowed = unique(wg.peers.flatMap(\.allowedIPs)).filter { hasV6 || !$0.contains(":") }
        if !allowed.isEmpty, !allowed.contains("0.0.0.0/0") {
            tun["route_address"] = allowed
        }

        var dns: [String: Any] = [
            "servers": [
                ["type": "udp", "tag": "vpn-dns",
                 "server": settings.vpnDNS ?? wg.dns.first ?? "1.1.1.1", "detour": "vpn"],
                ["type": "local", "tag": "local-dns"],
            ],
            // Домены и приложения, идущие напрямую, резолвятся местным DNS: иначе ответы
            // придут под зарубежный IP и сервис отдаст не тот узел.
            "rules": matchers.compactMap { rule, match -> [String: Any]? in
                guard rule.kind != .cidr, rule.action != .block else { return nil }
                return match.merging(["server": rule.action == .vpn ? "vpn-dns" : "local-dns"]) { a, _ in a }
            },
            "final": viaVPN ? "vpn-dns" : "local-dns",
        ]
        // Без IPv6 в туннеле AAAA-ответы уводили бы трафик мимо него.
        if !hasV6 { dns["strategy"] = "ipv4_only" }

        let base: [[String: Any]] = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"],
            ["ip_is_private": true, "outbound": "direct"],
        ]
        let user = matchers.map { rule, match -> [String: Any] in
            match.merging(rule.action == .block ? ["action": "reject"] : ["outbound": rule.action.rawValue]) { a, _ in a }
        }

        let config: [String: Any] = [
            "log": ["level": settings.debug ? "debug" : "info"],
            "dns": dns,
            "inbounds": [tun],
            "endpoints": [endpoint(wg: wg, corePort: corePort, hasV6: hasV6)],
            "outbounds": [["type": "direct", "tag": "direct"]],
            "route": [
                "auto_detect_interface": true,
                "default_domain_resolver": "local-dns",
                "final": viaVPN ? "vpn" : "direct",
                "rules": base + user,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func endpoint(wg: WGConfig, corePort: Int, hasV6: Bool) -> [String: Any] {
        let awg = wg.isAmnezia
        var ep: [String: Any] = [
            "type": awg ? "awg" : "wireguard", "tag": "vpn",
            "address": wg.addresses.map { $0.contains("/") ? $0 : $0 + ($0.contains(":") ? "/128" : "/32") },
            "private_key": wg.privateKey,
            "mtu": CoreConfig.tunnelMTU,
        ]
        for (key, value) in wg.amnezia {
            if awgInts.contains(key) {
                ep[key] = Int(value) ?? 0
            } else if let name = awgBools[key] {
                ep[name] = ["true", "1", "yes", "on"].contains(value.lowercased())
            } else {
                ep[awgRenamed[key] ?? key] = value
            }
        }
        ep["peers"] = wg.peers.map { peer -> [String: Any] in
            // Endpoint из конфига не нужен: пакеты уходят в локальный порт ядра.
            var p: [String: Any] = [
                "address": "127.0.0.1", "port": corePort, "public_key": peer.publicKey,
                "allowed_ips": peer.allowedIPs.isEmpty ? ["0.0.0.0/0"] + (hasV6 ? ["::/0"] : []) : peer.allowedIPs,
            ]
            if let psk = peer.presharedKey { p[awg ? "preshared_key" : "pre_shared_key"] = psk }
            if let keepalive = peer.persistentKeepalive { p["persistent_keepalive_interval"] = keepalive }
            return p
        }
        return ep
    }

    /// Примет ли движок такое правило - для проверки при вводе.
    public static func isValid(_ rule: RoutingRule) -> Bool {
        (try? matcher(for: rule)) != nil
    }

    /// Условие правила в терминах движка; бросает на значении, которое движок не примет.
    private static func matcher(for rule: RoutingRule) throws -> [String: Any] {
        let value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw EngineConfigError.invalidRule(id: rule.id) }
        switch rule.kind {
        case .app:
            guard value.hasPrefix("/") else { throw EngineConfigError.invalidRule(id: rule.id) }
            // У бандла много процессов (помощники, рендереры) - ловим всё внутри него.
            if value.hasSuffix(".app") {
                return ["process_path_regex": ["^" + escapeRegex(value) + "/"]]
            }
            return ["process_path": [value]]
        case .domain:
            return ["domain": [value.lowercased()]]
        case .domainSuffix:
            let suffix = value.lowercased().drop { $0 == "." }
            guard !suffix.isEmpty else { throw EngineConfigError.invalidRule(id: rule.id) }
            return ["domain_suffix": [String(suffix)]]
        case .domainKeyword:
            return ["domain_keyword": [value.lowercased()]]
        case .cidr:
            guard isCIDR(value) else { throw EngineConfigError.invalidRule(id: rule.id) }
            return ["ip_cidr": [value]]
        }
    }

    static func escapeRegex(_ s: String) -> String {
        s.reduce(into: "") { out, ch in
            if #"\.+*?()|[]{}^$"#.contains(ch) { out.append("\\") }
            out.append(ch)
        }
    }

    static func isCIDR(_ s: String) -> Bool {
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2, let ip = parts.first.map(String.init) else { return false }
        var v4 = in_addr(), v6 = in6_addr()
        let bits: Int
        if inet_pton(AF_INET, ip, &v4) == 1 { bits = 32 }
        else if inet_pton(AF_INET6, ip, &v6) == 1 { bits = 128 }
        else { return false }
        guard parts.count == 2 else { return true }
        guard let prefix = Int(parts[1]) else { return false }
        return (0...bits).contains(prefix)
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}
