import Foundation
import Testing
@testable import FreeTurnKit

let amneziaWG = """
[Interface]
PrivateKey = cHJpdmF0ZWtleXByaXZhdGVrZXlwcml2YXRla2V5MDA=
Address = 10.8.1.2/32
DNS = 9.9.9.9
Jc = 4
Jmin = 40
Jmax = 70
S1 = 15
S2 = 20
S3 = 12
S4 = 12
H1 = 1
H2 = 2
H3 = 3
H4 = 4
HeaderProtectionKey = aGVhZGVycHJvdGVjdGlvbmtleWhlYWRlcnByb3RlYzA=
RandomTrailers = true

[Peer]
PublicKey = cHVibGlja2V5cHVibGlja2V5cHVibGlja2V5cHViMDA=
PresharedKey = cHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrMDA=
AllowedIPs = 0.0.0.0/0
"""

private func rule(_ kind: RuleKind, _ value: String, _ action: RouteAction = .direct, enabled: Bool = true) -> RoutingRule {
    RoutingRule(kind: kind, value: value, action: action, enabled: enabled)
}

private func profile(_ rules: [RoutingRule] = [], default action: RouteAction = .vpn) -> RoutingProfile {
    RoutingProfile(name: "T", defaultAction: action, rules: rules)
}

private func engine(wg: String = plainWG, _ p: RoutingProfile = profile(),
                    settings: EngineSettings = EngineSettings()) throws -> [String: Any] {
    let json = try EngineConfig.build(wg: WGConfig.parse(wg), corePort: 41000, profile: p, settings: settings)
    return try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}

private func first(_ o: [String: Any], _ key: String) -> [String: Any] { (o[key] as! [[String: Any]])[0] }
private func routeRules(_ o: [String: Any]) -> [[String: Any]] { (o["route"] as! [String: Any])["rules"] as! [[String: Any]] }
private func userRules(_ o: [String: Any]) -> [[String: Any]] {
    let rules = routeRules(o)
    let baseCount = rules.first?["ip_version"] as? Int == 6 ? 4 : 3
    return Array(rules.dropFirst(baseCount))
}

@Test func engineWireguardEndpoint() throws {
    let ep = first(try engine(), "endpoints")
    #expect(ep["type"] as? String == "wireguard")
    #expect(ep["tag"] as? String == "vpn")
    #expect(ep["mtu"] as? Int == 1280)
    #expect(ep["address"] as? [String] == ["10.13.13.2/32"])
    #expect(ep["private_key"] as? String == "cHJpdmF0ZWtleXByaXZhdGVrZXlwcml2YXRla2V5MDA=")
    let peer = first(ep, "peers")
    #expect(peer["address"] as? String == "127.0.0.1")
    #expect(peer["port"] as? Int == 41000)
    #expect(peer["pre_shared_key"] as? String == "cHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrMDA=")
    #expect(peer["allowed_ips"] as? [String] == ["0.0.0.0/0", "::/0"])
    #expect(peer["persistent_keepalive_interval"] as? Int == 25)
}

@Test func engineAwgEndpoint() throws {
    let ep = first(try engine(wg: amneziaWG), "endpoints")
    #expect(ep["type"] as? String == "awg")
    #expect(ep["jc"] as? Int == 4)
    #expect(ep["s1"] as? Int == 15)
    #expect(ep["h1"] as? String == "1")
    #expect(ep["header_protection_key"] as? String == "aGVhZGVycHJvdGVjdGlvbmtleWhlYWRlcnByb3RlYzA=")
    #expect(ep["random_trailers"] as? Bool == true)
    let peer = first(ep, "peers")
    #expect(peer["preshared_key"] as? String == "cHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrcHNrMDA=")
    #expect(peer["pre_shared_key"] == nil)
}

@Test func engineTunInbound() throws {
    let tun = first(try engine(settings: EngineSettings(stack: "gvisor")), "inbounds")
    #expect(tun["type"] as? String == "tun")
    #expect(tun["mtu"] as? Int == 1280)
    #expect(tun["auto_route"] as? Bool == true)
    #expect(tun["stack"] as? String == "gvisor")
    #expect(tun["route_address"] == nil)
}

@Test func engineBaseRulesFirst() throws {
    let rules = routeRules(try engine(profile([rule(.domain, "a.com")])))
    #expect(rules[0] as NSDictionary == ["ip_version": 6, "action": "reject"])
    #expect(rules[1] as NSDictionary == ["action": "sniff"])
    #expect(rules[2] as NSDictionary == ["protocol": "dns", "action": "hijack-dns"])
    #expect(rules[3] as NSDictionary == ["ip_is_private": true, "outbound": "direct"])
    #expect(rules.count == 5)
}

@Test func engineRuleKinds() throws {
    let rules = userRules(try engine(profile([
        rule(.domain, "A.com"), rule(.domainSuffix, ".yandex.ru"), rule(.domainKeyword, "google", .vpn),
        rule(.cidr, "10.0.0.0/8"), rule(.cidr, "8.8.8.8"), rule(.domain, "off.com", enabled: false),
    ])))
    #expect(rules.count == 5)
    #expect(rules[0] as NSDictionary == ["domain": ["a.com"], "outbound": "direct"])
    #expect(rules[1] as NSDictionary == ["domain_suffix": ["yandex.ru"], "outbound": "direct"])
    #expect(rules[2] as NSDictionary == ["domain_keyword": ["google"], "outbound": "vpn"])
    #expect(rules[3] as NSDictionary == ["ip_cidr": ["10.0.0.0/8"], "outbound": "direct"])
    #expect(rules[4] as NSDictionary == ["ip_cidr": ["8.8.8.8"], "outbound": "direct"])
}

@Test func engineBlockIsReject() throws {
    let rules = userRules(try engine(profile([rule(.domainSuffix, "ads.example", .block)])))
    #expect(rules[0] as NSDictionary == ["domain_suffix": ["ads.example"], "action": "reject"])
}

// Путь уходит в регулярное выражение движка: спецсимволы обязаны быть экранированы.
@Test func engineAppBundleRegexEscaped() throws {
    let rules = userRules(try engine(profile([rule(.app, "/Applications/Яндекс Музыка (beta).app")])))
    #expect(rules[0]["process_path_regex"] as? [String] == [#"^/Applications/Яндекс Музыка \(beta\)\.app/"#])
    #expect(rules[0]["process_path"] == nil)
}

@Test func engineAppExecutablePath() throws {
    let rules = userRules(try engine(profile([rule(.app, "/usr/bin/curl")])))
    #expect(rules[0] as NSDictionary == ["process_path": ["/usr/bin/curl"], "outbound": "direct"])
}

@Test func engineDefaultModes() throws {
    let viaVPN = try engine()
    #expect((viaVPN["route"] as! [String: Any])["final"] as? String == "vpn")
    #expect((viaVPN["dns"] as! [String: Any])["final"] as? String == "vpn-dns")
    let viaDirect = try engine(profile(default: .direct))
    #expect((viaDirect["route"] as! [String: Any])["final"] as? String == "direct")
    #expect((viaDirect["dns"] as! [String: Any])["final"] as? String == "local-dns")
}

@Test func engineRouteBasics() throws {
    let route = try engine()["route"] as! [String: Any]
    #expect(route["auto_detect_interface"] as? Bool == true)
    #expect(route["default_domain_resolver"] as? String == "local-dns")
    #expect(first(try engine(), "outbounds") as NSDictionary == ["type": "direct", "tag": "direct"])
}

@Test func engineDnsServers() throws {
    let dns = try engine()["dns"] as! [String: Any]
    let servers = dns["servers"] as! [[String: Any]]
    #expect(servers[0] as NSDictionary == ["type": "udp", "tag": "vpn-dns", "server": "1.1.1.1", "detour": "vpn"])
    #expect(servers[1] as NSDictionary == ["type": "local", "tag": "local-dns"])
    let overridden = try engine(settings: EngineSettings(vpnDNS: "9.9.9.9"))["dns"] as! [String: Any]
    #expect((overridden["servers"] as! [[String: Any]])[0]["server"] as? String == "9.9.9.9")
    let noDNS = try engine(wg: "[Interface]\nPrivateKey=a\nAddress=10.0.0.2\n[Peer]\nPublicKey=p\n")["dns"] as! [String: Any]
    #expect((noDNS["servers"] as! [[String: Any]])[0]["server"] as? String == "1.1.1.1")
}

@Test func engineDnsRulesFollowRules() throws {
    let dns = try engine(profile([
        rule(.domainSuffix, "yandex.ru"), rule(.domain, "x.com", .vpn), rule(.app, "/usr/bin/curl"),
        rule(.cidr, "10.0.0.0/8"), rule(.domain, "ads.com", .block),
    ]))["dns"] as! [String: Any]
    let rules = dns["rules"] as! [[String: Any]]
    #expect(rules.count == 3)
    #expect(rules[0] as NSDictionary == ["domain_suffix": ["yandex.ru"], "server": "local-dns"])
    #expect(rules[1] as NSDictionary == ["domain": ["x.com"], "server": "vpn-dns"])
    #expect(rules[2] as NSDictionary == ["process_path": ["/usr/bin/curl"], "server": "local-dns"])
}

@Test func engineRejectsIPv6WhenTunnelCannotCarryIt() throws {
    let v4 = try engine(profile([rule(.cidr, "::/0")], default: .direct))
    #expect(first(v4, "inbounds")["address"] as? [String] == ["172.19.0.1/30", "fdfe:dcba:9876::1/126"])
    #expect(first(v4, "inbounds")["route_address"] == nil)
    #expect((v4["dns"] as! [String: Any])["strategy"] as? String == "ipv4_only")
    #expect(routeRules(v4)[0] as NSDictionary == ["ip_version": 6, "action": "reject"])
    #expect(userRules(v4)[0] as NSDictionary == ["ip_cidr": ["::/0"], "outbound": "direct"])

    let addressOnly = try engine(wg: "[Interface]\nPrivateKey=a\nAddress=10.0.0.2/32, fd00::2/128\n[Peer]\nPublicKey=p\nAllowedIPs=0.0.0.0/0\n")
    #expect((addressOnly["dns"] as! [String: Any])["strategy"] as? String == "ipv4_only")
    #expect(routeRules(addressOnly)[0] as NSDictionary == ["ip_version": 6, "action": "reject"])
}

@Test func engineCapturesIPv6EvenWithPartialAllowedIPs() throws {
    let v6 = try engine(wg: "[Interface]\nPrivateKey=a\nAddress=10.0.0.2/32, fd00::2/128\n[Peer]\nPublicKey=p\nAllowedIPs=10.0.0.0/8, fd00::/8\n")
    #expect(first(v6, "inbounds")["address"] as? [String] == ["172.19.0.1/30", "fdfe:dcba:9876::1/126"])
    #expect(first(v6, "inbounds")["route_address"] as? [String] == ["10.0.0.0/8"])
    #expect((v6["dns"] as! [String: Any])["strategy"] == nil)
    #expect(routeRules(v6)[0] as NSDictionary == ["action": "sniff"])
    #expect(first(first(v6, "endpoints"), "peers")["allowed_ips"] as? [String] == ["10.0.0.0/8", "fd00::/8"])
}

@Test func enginePartialAllowedIPsBecomeRouteAddress() throws {
    let o = try engine(wg: "[Interface]\nPrivateKey=a\nAddress=10.0.0.2\n[Peer]\nPublicKey=p\nAllowedIPs=10.0.0.0/8, 192.168.5.0/24\n")
    #expect(first(o, "inbounds")["route_address"] as? [String] == ["10.0.0.0/8", "192.168.5.0/24"])
}

@Test func engineEmptyAllowedIPsMeansEverything() throws {
    let o = try engine(wg: "[Interface]\nPrivateKey=a\nAddress=10.0.0.2\n[Peer]\nPublicKey=p\n")
    #expect(first(first(o, "endpoints"), "peers")["allowed_ips"] as? [String] == ["0.0.0.0/0"])
    #expect(first(o, "inbounds")["route_address"] == nil)
}

@Test func engineInvalidRulesThrow() throws {
    let empty = rule(.domain, "   ")
    #expect(throws: EngineConfigError.invalidRule(id: empty.id)) { try engine(profile([empty])) }
    for bad in ["10.0.0.0/33", "300.1.1.1", "abc", "10.0.0.0/"] {
        let r = rule(.cidr, bad)
        #expect(throws: EngineConfigError.invalidRule(id: r.id)) { try engine(profile([r])) }
    }
    let relative = rule(.app, "Safari.app")
    #expect(throws: EngineConfigError.invalidRule(id: relative.id)) { try engine(profile([relative])) }
    #expect(throws: Never.self) { try engine(profile([rule(.cidr, "fd00::/8"), rule(.domain, "bad", enabled: false)])) }
}

@Test func engineLogLevel() throws {
    #expect((try engine()["log"] as! [String: Any])["level"] as? String == "info")
    #expect((try engine(settings: EngineSettings(debug: true))["log"] as! [String: Any])["level"] as? String == "debug")
}

private let enginePath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("build/amnezia-box").path

/// Сгенерированный конфиг принимает сам движок (`make engine` должен быть выполнен).
@Test(.enabled(if: FileManager.default.isExecutableFile(atPath: enginePath)), arguments: [plainWG, amneziaWG])
func engineAcceptsGeneratedConfig(wg: String) throws {
    let p = profile([
        rule(.app, "/Applications/Safari.app"), rule(.app, "/usr/bin/curl"), rule(.domainSuffix, "yandex.ru"),
        rule(.domainKeyword, "google", .vpn), rule(.cidr, "10.0.0.0/8"), rule(.domain, "ads.example", .block),
    ])
    let json = try EngineConfig.build(wg: WGConfig.parse(wg), corePort: 41000, profile: p, settings: EngineSettings())
    let file = makeTempDir().appendingPathComponent("engine.json")
    try Data(json.utf8).write(to: file)
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: enginePath)
    proc.arguments = ["check", "-c", file.path]
    let pipe = Pipe()
    proc.standardError = pipe
    proc.standardOutput = pipe
    try proc.run()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    proc.waitUntilExit()
    #expect(proc.terminationStatus == 0, "engine rejected config: \(output)")
}

/// Эталон для Go-теста helper/internal/daemon/sanitize_test.go: служба обязана принимать
/// то, что собирает приложение. Перегенерация: FT_WRITE_FIXTURES=1 make test-app.
@Test func engineFixtureMatchesDaemonTestdata() throws {
    let p = RoutingProfile(id: "fixture", name: "fixture", defaultAction: .vpn, rules: [
        RoutingRule(id: "r1", kind: .app, value: "/Applications/Safari.app", action: .direct),
        RoutingRule(id: "r2", kind: .app, value: "/usr/bin/curl", action: .direct),
        RoutingRule(id: "r3", kind: .domainSuffix, value: "yandex.ru", action: .direct),
        RoutingRule(id: "r4", kind: .domainKeyword, value: "google", action: .vpn),
        RoutingRule(id: "r5", kind: .cidr, value: "10.0.0.0/8", action: .direct),
        RoutingRule(id: "r6", kind: .domain, value: "ads.example", action: .block),
    ])
    let json = try EngineConfig.build(wg: WGConfig.parse(amneziaWG), corePort: 41000, profile: p, settings: EngineSettings())
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("helper/internal/daemon/testdata/engine.json")
    if ProcessInfo.processInfo.environment["FT_WRITE_FIXTURES"] == "1" {
        try Data(json.utf8).write(to: url)
    }
    #expect(try String(contentsOf: url, encoding: .utf8) == json)
}
