import Foundation
import Testing
@testable import FreeTurnKit

private func link(_ extra: String = "", provider: String = "vk", peer: String = "1.2.3.4:56000") throws -> FreeturnLink {
    try FreeturnLink.parse(b64Link(#"{"v":1,"provider":"\#(provider)","peer":"\#(peer)"\#(extra)}"#))
}

@Test func importTcpModeRejected() throws {
    let l = try link(#","mode":"tcp""#)
    #expect(throws: ImportError.tcpModeUnsupported) { try ImportPlanner.draft(for: l, existing: []) }
}

@Test func importUnknownProviderRejected() throws {
    let l = try link(provider: "zzz")
    #expect(throws: ImportError.unknownProvider) { try ImportPlanner.draft(for: l, existing: []) }
}

@Test func importBadObfRejected() throws {
    let shortKey = try link(#","obf":"rtpopus3","key":"0123456789""#)
    #expect(throws: ImportError.badObf) { try ImportPlanner.draft(for: shortKey, existing: []) }
    let unknownProfile = try link(#","obf":"rot13","key":"\#(hex64)""#)
    #expect(throws: ImportError.badObf) { try ImportPlanner.draft(for: unknownProfile, existing: []) }
}

@Test func importRelayNeedsCallLinkDirectDoesNot() throws {
    #expect(try ImportPlanner.draft(for: link(), existing: []).needsCallLink)
    #expect(try !ImportPlanner.draft(for: link(provider: "direct"), existing: []).needsCallLink)
}

@Test func importCallLinkFromOwnerIsPrefilled() throws {
    let d = try ImportPlanner.draft(for: link(#","vk":" https://vk.ru/call/join/x ""#), existing: [])
    #expect(d.callLink == "https://vk.ru/call/join/x")
}

@Test func importLinkWithoutWgNeedsWireGuard() throws {
    #expect(try ImportPlanner.draft(for: link(), existing: []).needsWireGuard)
    #expect(try !ImportPlanner.draft(for: link(#","wg":"[Interface]""#), existing: []).needsWireGuard)
}

@Test func importDuplicatesDetected() throws {
    var existing = Server(name: "old")
    existing.client.serverAddress = "HOST.example:56000"
    existing.client.wireGuardConfig = "[Interface]\nPrivateKey = a"
    let d = try ImportPlanner.draft(
        for: link(#","wg":"  [Interface]\nPrivateKey = a\n""#, peer: "host.EXAMPLE:56000"), existing: [existing])
    #expect(d.duplicateAddress)
    #expect(d.duplicateConf)
    let fresh = try ImportPlanner.draft(for: link(), existing: [existing])
    #expect(!fresh.duplicateAddress)
    #expect(!fresh.duplicateConf)
}

@Test func importSuggestedName() throws {
    #expect(try ImportPlanner.draft(for: link(), existing: []).suggestedName == "1.2.3.4")
    #expect(try ImportPlanner.draft(for: link(#","name":"RU-1""#), existing: []).suggestedName == "RU-1")
}

@Test func importMakeServerMapsFields() throws {
    let l = try link(#","n":0,"spc":0,"timing":999,"transport":"udp","obf":"rtpopus3","key":"\#(hex64)","cid":" \#(hex32) ","dns":"zzz","dnss":"1.1.1.1; bad!token 8.8.8.8","mcap":true,"wg":" [Interface] ""#)
    let s = ImportPlanner.makeServer(from: try ImportPlanner.draft(for: l, existing: []), name: "  Мой  ", callLink: " L ")
    #expect(s.name == "Мой")
    #expect(s.client.serverAddress == "1.2.3.4:56000")
    #expect(s.client.callLink == "L")
    #expect(s.client.threads == 12)
    #expect(s.client.streamsPerCred == 12)
    #expect(s.client.useUdp)
    #expect(s.client.manualCaptcha)
    #expect(s.client.clientId == hex32)
    #expect(s.client.dnsMode == "auto")
    #expect(s.client.customDns == "1.1.1.1,8.8.8.8")
    #expect(s.client.tunnelTransport == "wireguard")
    #expect(s.client.wireGuardConfig == "[Interface]")
    #expect(s.opts.obfProfile == "rtpopus3")
    #expect(s.opts.obfKey == hex64)
    #expect(s.opts.obfTimingMs == 60)
}

@Test func importMakeServerNameFallsBackToSuggested() throws {
    let s = ImportPlanner.makeServer(from: try ImportPlanner.draft(for: link(), existing: []), name: "  ", callLink: "")
    #expect(s.name == "1.2.3.4")
    #expect(s.client.tunnelTransport == "none")
    #expect(s.opts.obfProfile == "none")
}
