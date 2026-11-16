import Foundation
import Testing
@testable import FreeTurnKit

private func payload(_ link: String) -> String {
    var b64 = String(link.dropFirst("freeturn://".count)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
    return String(decoding: Data(base64Encoded: b64)!, as: UTF8.self)
}

// Тот же байт-в-байт эталон, что у Android-клиента (FreeturnLinkTest.golden minimal).
@Test func encodeGoldenMinimal() throws {
    #expect(try FreeturnLink.parse(goldenMinimal).encode() == goldenMinimal)
}

// Порядок ключей - как у Go json.Marshal и Android: иначе ссылки разных клиентов не совпадут.
@Test func encodeFollowsGoFieldOrder() throws {
    var link = FreeturnLink()
    link.provider = "vk"; link.peer = "1.2.3.4:56000"; link.transport = "udp"
    link.obfProfile = "rtpopus3"; link.obfKey = hex64; link.obfTimingMs = 20
    link.n = 10; link.streamsPerCred = 6; link.clientId = hex32; link.dnsMode = "doh"; link.dnsServers = "1.1.1.1"
    link.manualCaptcha = true; link.name = "RU \"1\""; link.callLink = "https://vk.ru/call/join/x"; link.wgConf = "[Interface]\nA = b"
    #expect(payload(link.encode()) == #"{"v":1,"provider":"vk","peer":"1.2.3.4:56000","transport":"udp","obf":"rtpopus3","key":"\#(hex64)","timing":20,"n":10,"spc":6,"cid":"\#(hex32)","dns":"doh","dnss":"1.1.1.1","mcap":true,"name":"RU \"1\"","vk":"https://vk.ru/call/join/x","wg":"[Interface]\nA = b"}"#)
    #expect(try FreeturnLink.parse(link.encode()) == link)
}

@Test func encodeOmitsObfNoneAndEmpty() throws {
    var link = FreeturnLink()
    link.provider = "direct"; link.peer = "h:1"; link.obfProfile = "none"; link.obfKey = "zz"
    #expect(payload(link.encode()) == #"{"v":1,"provider":"direct","peer":"h:1"}"#)
}

private func server() -> Server {
    var s = Server(name: "Нидерланды")
    s.client.serverAddress = "203.0.113.10:56000"
    s.client.callLink = "https://vk.ru/call/join/mine"
    s.client.useUdp = true
    s.client.threads = 8
    s.client.tunnelTransport = "wireguard"
    s.client.wireGuardConfig = "# комментарий\n[Interface]\nPrivateKey = a\nMTU = 1420\n\n[Peer]\nPublicKey = b\n; ещё\nAllowedIPs = 0.0.0.0/0\n"
    s.opts.obfProfile = "rtpopus3"; s.opts.obfKey = hex64; s.opts.obfTimingMs = 20
    return s
}

@Test func shareBuildsUsableLink() throws {
    let link = try FreeturnLink.parse(ShareLinkBuilder.build(server: server(), ownClientId: hex32,
                                                             options: ShareOptions(name: " Ноутбук ", includeCallLink: false, includeWireGuard: true)))
    #expect(link.provider == "vk")
    #expect(link.peer == "203.0.113.10:56000")
    #expect(link.transport == "udp")
    #expect(link.obfProfile == "rtpopus3")
    #expect(link.obfKey == hex64)
    #expect(link.obfTimingMs == 20)
    #expect(link.n == 8)
    #expect(link.clientId == hex32)
    #expect(link.name == "Ноутбук")
    #expect(link.callLink == "")
    // Комментарии, пустые строки и MTU срезаны: короче ссылка, плотнее QR. MTU у получателя - своя константа.
    #expect(link.wgConf == "[Interface]\nPrivateKey = a\n[Peer]\nPublicKey = b\nAllowedIPs = 0.0.0.0/0")
    // Получатель импортирует её без ошибок.
    let draft = try ImportPlanner.draft(for: link, existing: [])
    #expect(draft.needsCallLink)
    #expect(!draft.needsWireGuard)
}

@Test func shareOptions() throws {
    var s = server()
    s.client.clientId = "fromlink"
    let link = try FreeturnLink.parse(ShareLinkBuilder.build(server: s, ownClientId: hex32,
                                                             options: ShareOptions(name: "", includeCallLink: true, includeWireGuard: false)))
    #expect(link.callLink == "https://vk.ru/call/join/mine")
    #expect(link.wgConf == "")
    #expect(link.clientId == "fromlink")
    #expect(link.name == "Нидерланды")
    s.opts.obfKey = "bad"
    #expect(try FreeturnLink.parse(ShareLinkBuilder.build(server: s, ownClientId: hex32, options: ShareOptions())).obfProfile == "")
}
