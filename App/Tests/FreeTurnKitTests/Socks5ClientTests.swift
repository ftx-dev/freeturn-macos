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

/// Локальный сервер на 127.0.0.1: принимает одно соединение и отвечает [reply] (пусто - закрывает).
private func fakeServer(reply: [UInt8]) throws -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let ok = withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0 }
    }
    try #require(ok && listen(fd, 1) == 0)
    let port = Int(in_port_t(bigEndian: addr.sin_port))
    Thread.detachNewThread {
        let client = accept(fd, nil, nil)
        var buf = [UInt8](repeating: 0, count: 8)
        _ = recv(client, &buf, buf.count, 0)
        if !reply.isEmpty { _ = send(client, reply, reply.count, 0) }
        close(client)
        close(fd)
    }
    return port
}

// Последовательно: потоки фейковых серверов закрывают дескрипторы, номера которых могут достаться соседнему тесту.
@Suite(.serialized) struct Socks5ProbeTests {
    @Test func socks5ProbeAcceptsWorkingProxy() throws {
        let port = try fakeServer(reply: [5, 0])
        #expect(Socks5Probe.check(Socks5ClientConfig(host: "127.0.0.1", port: port)) == nil)
    }

    @Test func socks5ProbeReportsSilentServer() throws {
        let port = try fakeServer(reply: [])
        #expect(Socks5Probe.check(Socks5ClientConfig(host: "127.0.0.1", port: port), timeout: 2) != nil)
    }

    @Test func socks5ProbeReportsRejectedAuth() throws {
        let port = try fakeServer(reply: [5, 0xFF])
        #expect(Socks5Probe.check(Socks5ClientConfig(host: "127.0.0.1", port: port))?.contains("логин") == true)
    }
}
