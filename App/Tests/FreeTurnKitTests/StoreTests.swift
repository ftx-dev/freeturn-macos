import Foundation
import Testing
@testable import FreeTurnKit

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ft-" + UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func missingFileReturnsDefault() throws {
    let store = Store(directory: makeTempDir())
    let file = try store.load(ServersFile.self, from: "servers.json", default: ServersFile())
    #expect(file.list.isEmpty)
    #expect(file.activeId == nil)
}

@Test func saveThenLoad() throws {
    let store = Store(directory: makeTempDir())
    let server = Server(name: "A")
    try store.save(ServersFile(list: [server], activeId: server.id), to: "servers.json")
    let file = try store.load(ServersFile.self, from: "servers.json", default: ServersFile())
    #expect(file.active == server)
}

@Test func saveSetsMode0600() throws {
    let dir = makeTempDir()
    try Store(directory: dir).save(AppSettings(), to: "settings.json")
    let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("settings.json").path)
    #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func saveIsAtomic() throws {
    let dir = makeTempDir()
    let store = Store(directory: dir)
    try store.save(AppSettings(), to: "settings.json")
    try store.save(AppSettings(), to: "settings.json")
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(names == ["settings.json"])
}

// Битый файл не затирается дефолтом: иначе один сбой записи стирал бы все серверы.
@Test func corruptFileThrowsAndIsKept() throws {
    let dir = makeTempDir()
    let path = dir.appendingPathComponent("servers.json")
    try Data(#"{"list":["#.utf8).write(to: path)
    let store = Store(directory: dir)
    #expect(throws: StoreError.corrupt("servers.json")) {
        try store.load(ServersFile.self, from: "servers.json", default: ServersFile())
    }
    #expect(try String(contentsOf: path, encoding: .utf8) == #"{"list":["#)
}

@Test func ownClientIdIsStable32Hex() throws {
    let store = Store(directory: makeTempDir())
    let a = try store.ownClientId()
    let b = try store.ownClientId()
    #expect(a == b)
    #expect(a.count == 32)
    #expect(a.allSatisfy { $0.isHexDigit && !$0.isUppercase })
}

@Test func createsDirectoryOnSave() throws {
    let dir = makeTempDir().appendingPathComponent("nested/dir")
    try Store(directory: dir).save(AppSettings(), to: "settings.json")
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.json").path))
}
