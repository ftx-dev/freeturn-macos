import Foundation
import Testing
@testable import FreeTurnKit

private let sample = RoutingProfile(name: "Работа", defaultAction: .direct, rules: [
    RoutingRule(kind: .app, value: "/Applications/Safari.app", action: .vpn),
    RoutingRule(kind: .domainSuffix, value: "example.com", action: .block, enabled: false),
])

@Test func exportImportRoundTrip() throws {
    let back = try ProfileTransfer.importProfile(ProfileTransfer.export(sample))
    #expect(back.name == sample.name)
    #expect(back.defaultAction == sample.defaultAction)
    #expect(back.rules.map(\.kind) == sample.rules.map(\.kind))
    #expect(back.rules.map(\.value) == sample.rules.map(\.value))
    #expect(back.rules.map(\.action) == sample.rules.map(\.action))
    #expect(back.rules.map(\.enabled) == sample.rules.map(\.enabled))
}

@Test func importAssignsFreshIdsAndClearsBuiltIn() throws {
    let back = try ProfileTransfer.importProfile(ProfileTransfer.export(Presets.russiaDirect))
    #expect(!back.builtIn)
    #expect(back.id != Presets.russiaDirect.id)
    #expect(Set(back.rules.map(\.id)).isDisjoint(with: Presets.russiaDirect.rules.map(\.id)))
}

@Test func importRejectsWrongFormat() {
    #expect(throws: ProfileTransferError.wrongFormat) { try ProfileTransfer.importProfile(Data(#"{"hello":1}"#.utf8)) }
    #expect(throws: ProfileTransferError.wrongFormat) { try ProfileTransfer.importProfile(Data("not json".utf8)) }
    #expect(throws: ProfileTransferError.wrongFormat) {
        try ProfileTransfer.importProfile(Data(#"{"format":"freeturn-routing","version":1,"profile":{"name":5}}"#.utf8))
    }
}

@Test func importRejectsNewerVersion() {
    #expect(throws: ProfileTransferError.unsupportedVersion) {
        try ProfileTransfer.importProfile(Data(#"{"format":"freeturn-routing","version":2,"profile":{}}"#.utf8))
    }
}
