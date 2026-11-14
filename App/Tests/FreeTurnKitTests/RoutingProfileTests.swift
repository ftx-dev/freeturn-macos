import Foundation
import Testing
@testable import FreeTurnKit

@Test func presetRussiaDirect() {
    let p = Presets.russiaDirect
    #expect(p.builtIn)
    #expect(p.defaultAction == .vpn)
    #expect(!p.rules.isEmpty)
    #expect(p.rules.allSatisfy { $0.action == .direct && $0.enabled })
    let suffixes = Set(p.rules.filter { $0.kind == .domainSuffix }.map(\.value))
    for d in ["vk.com", "yandex.ru", "gosuslugi.ru", "sberbank.ru", "ozon.ru", "wildberries.ru", "ru", "xn--p1ai"] {
        #expect(suffixes.contains(d), "нет \(d)")
    }
}

@Test func presetAllViaVPN() {
    #expect(Presets.allViaVPN.builtIn)
    #expect(Presets.allViaVPN.rules.isEmpty)
    #expect(Presets.allViaVPN.defaultAction == .vpn)
}

@Test func presetsBuildValidEngineConfig() throws {
    _ = try EngineConfig.build(wg: WGConfig.parse(plainWG), corePort: 1, profile: Presets.russiaDirect, settings: EngineSettings())
}

@Test func profileForServerPrefersOwnThenShared() {
    let own = RoutingProfile(name: "own", defaultAction: .direct, rules: [])
    let shared = RoutingProfile(name: "shared", defaultAction: .vpn, rules: [])
    let file = RoutingFile(profiles: [own, shared], sharedProfileId: shared.id)
    var server = Server(name: "S")
    #expect(file.profile(for: server) == shared)
    server.client.routingProfileId = own.id
    #expect(file.profile(for: server) == own)
    server.client.routingProfileId = "gone"
    #expect(file.profile(for: server) == shared)
    #expect(RoutingFile(profiles: [], sharedProfileId: "gone").profile(for: server) == Presets.allViaVPN)
}

@Test func routingProfileRoundTrips() throws {
    let p = RoutingProfile(name: "P", defaultAction: .direct, rules: [RoutingRule(kind: .app, value: "/a.app", action: .block)])
    #expect(try JSONDecoder().decode(RoutingProfile.self, from: JSONEncoder().encode(p)) == p)
}
