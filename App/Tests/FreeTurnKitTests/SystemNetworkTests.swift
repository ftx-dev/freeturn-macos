import Foundation
import Testing
@testable import FreeTurnKit

@Test func snapshotFromPhysicalInterface() {
    let s = SystemNetwork.snapshot(primaryInterface: "en0", dns: ["192.168.1.1"]) { _ in 14 }
    #expect(s == NetworkSnapshot(ifName: "en0", ifIndex: 14, dns: ["192.168.1.1"]))
}

// Чужой VPN держит default route: привязка ядра к utun завернула бы трафик в туннель.
@Test func snapshotRejectsTunnelAndLoopback() {
    #expect(SystemNetwork.snapshot(primaryInterface: "utun4", dns: []) { _ in 20 } == nil)
    #expect(SystemNetwork.snapshot(primaryInterface: "lo0", dns: []) { _ in 1 } == nil)
    #expect(SystemNetwork.snapshot(primaryInterface: nil, dns: []) { _ in 1 } == nil)
    #expect(SystemNetwork.snapshot(primaryInterface: "", dns: []) { _ in 1 } == nil)
}

@Test func snapshotRejectsUnknownIndex() {
    #expect(SystemNetwork.snapshot(primaryInterface: "en9", dns: []) { _ in 0 } == nil)
}

@Test func freeUDPPortIsBindable() throws {
    let port = try PortPicker.freeUDPPort()
    #expect((1024...65535).contains(port))
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(port).bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    #expect(rc == 0)
}
