import Foundation
import Testing
@testable import FreeTurnKit

private func build(_ edit: (inout Server) -> Void = { _ in }, systemDNS: [String] = ["192.168.1.1"],
                   advancedCaptcha: Bool = false) -> [String: Any] {
    var s = Server(name: "S")
    s.client.serverAddress = "1.2.3.4:56000"
    s.client.callLink = "L"
    edit(&s)
    let json = CoreConfig.build(server: s, listenPort: 41000, ownClientId: hex32,
                                systemDNS: systemDNS, advancedCaptcha: advancedCaptcha)
    return try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}

private func sub(_ o: [String: Any], _ key: String) -> [String: Any] { o[key] as! [String: Any] }

@Test func coreFixedFields() {
    let o = build()
    #expect(sub(o, "tunnel") as NSDictionary == ["mode": "none", "config": "", "mtu": 1280])
    #expect(sub(o, "proxy") as NSDictionary == ["mode": "udp", "listen": "127.0.0.1:41000"])
    #expect(sub(o, "vk")["platform"] as? String == "desktop")
    #expect(o["routes"] as? Bool == false)
    #expect(o["subUrl"] as? String == "")
    #expect(o["peer"] as? String == "1.2.3.4:56000")
    #expect(sub(o, "turn")["port"] as? String == "")
    #expect(sub(o, "log")["debug"] as? Bool == false)
}

// Декодер ядра строгий: лишний ключ - отказ, kcp вне tcp-режима - отказ.
@Test func coreTopLevelKeysExact() {
    #expect(Set(build().keys) == ["peer", "clientId", "subUrl", "provider", "routes",
                                  "turn", "proxy", "vk", "obf", "dns", "log", "tunnel"])
}

@Test func coreDirectUsesOneThread() {
    #expect(sub(build { $0.client.provider = "direct"; $0.client.threads = 10 }, "turn")["n"] as? Int == 1)
}

@Test func coreRelayThreadsAndLink() {
    let o = build { $0.client.threads = 10; $0.client.streamsPerCred = 7 }
    #expect(sub(o, "turn")["n"] as? Int == 10)
    #expect(sub(o, "vk")["links"] as? [String] == ["L"])
    #expect(sub(o, "vk")["streamsPerCred"] as? Int == 7)
}

@Test func coreNonPositiveThreadsFallBackToDefault() {
    let o = build { $0.client.threads = 0; $0.client.streamsPerCred = -1 }
    #expect(sub(o, "turn")["n"] as? Int == 12)
    #expect(sub(o, "vk")["streamsPerCred"] as? Int == 12)
}

@Test func coreTransport() {
    #expect(sub(build(), "turn")["transport"] as? String == "tcp")
    #expect(sub(build { $0.client.useUdp = true }, "turn")["transport"] as? String == "udp")
}

@Test func coreMagicTurn() {
    #expect(sub(build { $0.client.magicTurn = " 9.9.9.9 " }, "turn")["host"] as? String == "")
    #expect(sub(build { $0.client.magicSwitch = true; $0.client.magicTurn = " 9.9.9.9 " }, "turn")["host"] as? String == "9.9.9.9")
}

@Test func coreObf() {
    let off = build { $0.opts.obfKey = hex64; $0.opts.obfTimingMs = 20 }
    #expect(sub(off, "obf") as NSDictionary == ["profile": "none", "key": "", "timingMs": 0])
    let on = build { $0.opts.obfProfile = "rtpopus3"; $0.opts.obfKey = hex64; $0.opts.obfTimingMs = 20 }
    #expect(sub(on, "obf") as NSDictionary == ["profile": "rtpopus3", "key": hex64, "timingMs": 20])
}

@Test func coreClientId() {
    #expect(build()["clientId"] as? String == hex32)
    #expect(build { $0.client.clientId = "fromlink" }["clientId"] as? String == "fromlink")
}

@Test func coreDnsPriority() {
    #expect(sub(build { $0.client.customDns = "8.8.8.8, 1.1.1.1" }, "dns")["servers"] as? [String] == ["8.8.8.8", "1.1.1.1"])
    #expect(sub(build(), "dns")["servers"] as? [String] == ["192.168.1.1"])
    #expect(sub(build { $0.client.useCarrierDns = false }, "dns")["servers"] as? [String] == [])
    #expect(sub(build { $0.client.dnsMode = "doh" }, "dns")["mode"] as? String == "doh")
}

@Test func coreCaptchaFlags() {
    let auto = sub(build(advancedCaptcha: true), "vk")
    #expect(auto["autoCaptcha"] as? Bool == true)
    #expect(auto["advancedCaptcha"] as? Bool == true)
    #expect(auto["manualCaptcha"] as? Bool == false)
    let manual = sub(build({ $0.client.manualCaptcha = true }, advancedCaptcha: true), "vk")
    #expect(manual["manualCaptcha"] as? Bool == true)
    #expect(manual["advancedCaptcha"] as? Bool == false)
    #expect(manual["autoCaptcha"] as? Bool == true)
}

@Test func coreDebugFlag() {
    #expect(sub(build { $0.client.debugMode = true }, "log")["debug"] as? Bool == true)
}

/// Эталоны для Go-теста helper/internal/bridge/fixture_test.go: их проверяет декодер ядра.
/// Перегенерация: FT_WRITE_FIXTURES=1 make test-app.
@Test(arguments: ["direct", "relay"]) func coreFixtureMatchesHelperTestdata(kind: String) throws {
    var s = Server(name: "fixture")
    s.client.serverAddress = "1.2.3.4:56000"
    s.client.provider = kind == "direct" ? "direct" : "vk"
    s.client.callLink = kind == "direct" ? "" : "https://vk.ru/call/join/fixture"
    s.opts.obfProfile = "rtpopus3"
    s.opts.obfKey = hex64
    s.opts.obfTimingMs = 20
    let json = CoreConfig.build(server: s, listenPort: 41000, ownClientId: hex32,
                                systemDNS: ["192.168.1.1"], advancedCaptcha: true)
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("helper/internal/bridge/testdata/core-config-\(kind).json")
    if ProcessInfo.processInfo.environment["FT_WRITE_FIXTURES"] == "1" {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }
    #expect(try String(contentsOf: url, encoding: .utf8) == json)
}
