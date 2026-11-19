import Foundation
import Testing
@testable import FreeTurnKit

@Test func addActivates() {
    var file = ServersFile()
    let a = Server(name: "A"), b = Server(name: "B")
    file.add(a, activate: true)
    file.add(b, activate: false)
    #expect(file.list == [a, b])
    #expect(file.activeId == a.id)
    file.add(Server(name: "C"), activate: true)
    #expect(file.active?.name == "C")
}

@Test func firstServerBecomesActiveEvenWithoutActivate() {
    var file = ServersFile()
    let a = Server(name: "A")
    file.add(a, activate: false)
    #expect(file.activeId == a.id)
}

@Test func removeActiveSelectsFirstRemaining() {
    let a = Server(name: "A"), b = Server(name: "B")
    var file = ServersFile(list: [a, b], activeId: b.id)
    file.remove(id: b.id)
    #expect(file.list == [a])
    #expect(file.activeId == a.id)
}

@Test func removeInactiveKeepsActive() {
    let a = Server(name: "A"), b = Server(name: "B")
    var file = ServersFile(list: [a, b], activeId: b.id)
    file.remove(id: a.id)
    #expect(file.activeId == b.id)
}

@Test func removeLastClearsActive() {
    let a = Server(name: "A")
    var file = ServersFile(list: [a], activeId: a.id)
    file.remove(id: a.id)
    #expect(file.list.isEmpty)
    #expect(file.activeId == nil)
}

@Test func cloneCopiesWithNewIdAndSuffixedName() {
    var a = Server(name: "RU")
    a.client.serverAddress = "1.2.3.4:56000"
    var file = ServersFile(list: [a], activeId: a.id)
    let copy = file.clone(id: a.id)
    #expect(copy?.name == "RU (копия)")
    #expect(copy?.id != a.id)
    #expect(copy?.client == a.client)
    #expect(file.list.count == 2)
    #expect(file.list[1] == copy)
    #expect(file.activeId == a.id)
    #expect(file.clone(id: "missing") == nil)
}

@Test func renameTrimsAndKeepsOldOnEmpty() {
    let a = Server(name: "Old")
    var file = ServersFile(list: [a], activeId: a.id)
    file.rename(id: a.id, to: "  New  ")
    #expect(file.list[0].name == "New")
    file.rename(id: a.id, to: "   ")
    #expect(file.list[0].name == "New")
}

@Test func updateReplacesById() {
    var a = Server(name: "A")
    var file = ServersFile(list: [a], activeId: a.id)
    a.client.threads = 5
    file.update(a)
    #expect(file.list[0].client.threads == 5)
    file.update(Server(name: "stranger"))
    #expect(file.list.count == 1)
}

@Test func streamLimitsClampAllSavedServersWhenTurnedOff() {
    var active = Server(name: "A")
    active.client.threads = 100
    active.client.streamsPerCred = 50
    var inactive = Server(name: "B")
    inactive.client.threads = 30
    inactive.client.streamsPerCred = 12
    var file = ServersFile(list: [active, inactive], activeId: active.id)
    var settings = AppSettings()
    settings.increasedStreamLimits = true

    let appliedIncreasedLimits = file.enforceStreamLimits(settings)
    #expect(appliedIncreasedLimits)
    #expect(file.list.map(\.client.threads) == [96, 30])
    #expect(file.list.map(\.client.streamsPerCred) == [48, 12])

    settings.increasedStreamLimits = false
    let appliedStandardLimits = file.enforceStreamLimits(settings)
    #expect(appliedStandardLimits)
    #expect(file.list.map(\.client.threads) == [24, 24])
    #expect(file.list.map(\.client.streamsPerCred) == [24, 12])
    #expect(file.activeId == active.id)
}
