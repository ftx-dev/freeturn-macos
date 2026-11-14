import Foundation
import Testing
@testable import FreeTurnKit

private func decodeServer(_ json: String) throws -> Server {
    try JSONDecoder().decode(Server.self, from: Data(json.utf8))
}

@Test func decodesAndroidShape() throws {
    let s = try decodeServer("""
    {"id":"abc","name":"RU",
     "ssh":{"ip":"1.2.3.4","port":22,"username":"root","password":"p"},
     "client":{"serverAddress":"1.2.3.4:56000","callLink":"https://vk.ru/call/join/x","provider":"vk",
               "threads":10,"useUdp":true,"localPort":"127.0.0.1:9000","tunnelTransport":"wireguard",
               "wireGuardConfig":"[Interface]","splitTunnelMode":"exclude"},
     "proxyListen":"0.0.0.0:56000","proxyConnect":"127.0.0.1:40537",
     "opts":{"obfProfile":"rtpopus3","obfKey":"k","obfTimingMs":20,"proxyMode":"udp",
             "kcp":{"noDelay":1,"interval":20},"method":"docker"}}
    """)
    #expect(s.id == "abc")
    #expect(s.client.serverAddress == "1.2.3.4:56000")
    #expect(s.client.threads == 10)
    #expect(s.client.useUdp)
    #expect(s.client.wireGuardActive)
    #expect(s.opts.obfProfile == "rtpopus3")
    #expect(s.opts.obfTimingMs == 20)
    #expect(s.opts.obfEnabled)
}

@Test func missingFieldsUseDefaults() throws {
    let s = try decodeServer(#"{"id":"a","name":"n"}"#)
    #expect(s.client.threads == 12)
    #expect(s.client.streamsPerCred == 12)
    #expect(s.client.provider == "vk")
    #expect(s.client.dnsMode == "auto")
    #expect(s.client.useCarrierDns)
    #expect(s.client.tunnelTransport == "none")
    #expect(!s.client.wireGuardActive)
    #expect(s.opts.proxyMode == "udp")
    #expect(s.opts.obfProfile == "none")
    #expect(!s.opts.obfEnabled)
}

@Test func unknownProviderFallsBackToRelay() throws {
    let s = try decodeServer(#"{"id":"a","name":"n","client":{"provider":"xyz"}}"#)
    #expect(s.client.provider == "vk")
}

@Test func serverRoundTrips() throws {
    var s = Server(name: "X")
    s.client.serverAddress = "5.6.7.8:1"
    s.client.routingProfileId = "p1"
    let back = try JSONDecoder().decode(Server.self, from: JSONEncoder().encode(s))
    #expect(back == s)
}

@Test func obfKeyValidation() {
    #expect(ObfProfile.isValidKey(String(repeating: "aF09", count: 16)))
    #expect(!ObfProfile.isValidKey(String(repeating: "a", count: 63)))
    #expect(!ObfProfile.isValidKey(String(repeating: "g", count: 64)))
}
