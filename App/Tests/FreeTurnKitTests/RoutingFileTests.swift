import Foundation
import Testing
@testable import FreeTurnKit

@Test func initialHasBothPresetsAndSharedIsRussiaDirect() {
    let file = RoutingFile.initial()
    #expect(file.profiles == [Presets.allViaVPN, Presets.russiaDirect])
    #expect(file.sharedProfileId == Presets.russiaDirect.id)
}

@Test func newSettingsDefaults() {
    let s = AppSettings()
    #expect(s.appIcon == "x")
    #expect(s.advancedCaptcha)
    // Старые настройки без этих ключей тоже получают новые значения по умолчанию.
    let old = try! JSONDecoder().decode(AppSettings.self, from: Data(#"{"theme":"dark"}"#.utf8))
    #expect(old.appIcon == "x" && old.advancedCaptcha)
}

@Test func builtInProfileCannotBeRemovedOrChanged() {
    var file = RoutingFile.initial()
    file.remove(id: Presets.russiaDirect.id)
    #expect(file.profiles.count == 2)
    var edited = Presets.russiaDirect
    edited.rules = []
    file.update(edited)
    #expect(file.profiles[1] == Presets.russiaDirect)
}

@Test func removingSharedFallsBackToAllViaVPN() {
    var file = RoutingFile.initial()
    let mine = RoutingProfile(name: "mine", defaultAction: .direct, rules: [])
    file.add(mine)
    file.sharedProfileId = mine.id
    file.remove(id: mine.id)
    #expect(file.profiles.count == 2)
    #expect(file.sharedProfileId == Presets.allViaVPN.id)
}

@Test func cloneMakesEditableCopyWithFreshIds() throws {
    var file = RoutingFile.initial()
    let cloned = file.clone(id: Presets.russiaDirect.id)
    let copy = try #require(cloned)
    #expect(copy.name == Presets.russiaDirect.name + " (копия)")
    #expect(!copy.builtIn)
    #expect(copy.id != Presets.russiaDirect.id)
    #expect(copy.rules.count == Presets.russiaDirect.rules.count)
    #expect(Set(copy.rules.map(\.id)).isDisjoint(with: Presets.russiaDirect.rules.map(\.id)))
    #expect(file.profiles.last == copy)
    #expect(file.clone(id: "missing") == nil)
}

@Test func updateReplacesOwnProfile() {
    var file = RoutingFile.initial()
    var mine = RoutingProfile(name: "mine", defaultAction: .vpn, rules: [])
    file.add(mine)
    mine.defaultAction = .direct
    file.update(mine)
    #expect(file.profiles.last?.defaultAction == .direct)
}

// Пресеты в файле на диске могли устареть или пропасть: при загрузке берутся актуальные.
@Test func normalizedRestoresCurrentBuiltIns() {
    var stale = Presets.russiaDirect
    stale.rules = []
    let mine = RoutingProfile(name: "mine", defaultAction: .vpn, rules: [])
    let file = RoutingFile(profiles: [mine, stale], sharedProfileId: "gone").normalized()
    #expect(file.profiles == [Presets.allViaVPN, Presets.russiaDirect, mine])
    #expect(file.sharedProfileId == Presets.allViaVPN.id)
}

@Test func ruleValidation() {
    #expect(EngineConfig.isValid(RoutingRule(kind: .cidr, value: "10.0.0.0/8", action: .direct)))
    #expect(!EngineConfig.isValid(RoutingRule(kind: .cidr, value: "10.0.0.0/99", action: .direct)))
    #expect(!EngineConfig.isValid(RoutingRule(kind: .domain, value: " ", action: .direct)))
    #expect(EngineConfig.isValid(RoutingRule(kind: .app, value: "/Applications/Safari.app", action: .direct)))
    #expect(!EngineConfig.isValid(RoutingRule(kind: .app, value: "Safari", action: .direct)))
}
