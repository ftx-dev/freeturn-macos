import Foundation
import Testing
@testable import FreeTurnKit

private func json(_ s: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
}

@Test func socks5ConfigRoutesEverythingToTheProxy() throws {
    let cfg = try json(Socks5ClientConfig(host: " 192.168.43.1 ", port: 1080).engineConfig(mtu: 1280))
    let outbounds = try #require(cfg["outbounds"] as? [[String: Any]])
    let socks = try #require(outbounds.first { $0["tag"] as? String == "socks" })
    #expect(socks["server"] as? String == "192.168.43.1")
    #expect(socks["server_port"] as? Int == 1080)
    #expect(socks["username"] == nil)
    let route = try #require(cfg["route"] as? [String: Any])
    #expect(route["final"] as? String == "socks")
    let dns = try #require(cfg["dns"] as? [String: Any])
    let servers = try #require(dns["servers"] as? [[String: Any]])
    // DNS - по TCP через прокси: работает и без UDP на раздающем телефоне.
    #expect(servers.contains { $0["type"] as? String == "tcp" && $0["detour"] as? String == "socks" })
}

@Test func socks5ConfigAddsCredentialsOnlyWhenSet() throws {
    let cfg = try json(Socks5ClientConfig(host: "h", port: 1, user: "u", password: "p").engineConfig(mtu: 1280))
    let socks = try #require((cfg["outbounds"] as? [[String: Any]])?.first)
    #expect(socks["username"] as? String == "u")
    #expect(socks["password"] as? String == "p")
}

@Test func socks5ConfigValidation() {
    #expect(Socks5ClientConfig(host: "10.0.0.1", port: 1080).isValid)
    #expect(!Socks5ClientConfig(host: "  ", port: 1080).isValid)
    #expect(!Socks5ClientConfig(host: "10.0.0.1", port: 0).isValid)
    #expect(!Socks5ClientConfig(host: "10.0.0.1", port: 70000).isValid)
}

@Test func socks5ConfigPersists() throws {
    let defaults = try #require(UserDefaults(suiteName: "socks5-test-\(UUID())"))
    let saved = Socks5ClientConfig(host: "192.168.43.1", port: 1081, user: "a", password: "b")
    saved.save(defaults)
    #expect(Socks5ClientConfig.load(defaults) == saved)
}
