import Foundation
import Testing
@testable import FreeTurnKit

private let key64 = String(repeating: "ab12", count: 16)
private let id32 = String(repeating: "cd34", count: 8)

@Test func decodesColorsFromEngineLogs() throws {
    let line = LogLine(level: .info, source: .engine,
                       text: "\u{1B}[36mINFO\u{1B}[0m [\u{1B}[38;5;215m2763569863\u{1B}[0m 1ms] соединение")
    let segments = try #require(line.segments)
    #expect(line.text == "INFO [2763569863 1ms] соединение")
    #expect(segments.map(\.text) == ["INFO", " [", "2763569863", " 1ms] соединение"])
    #expect(segments.map(\.foreground) == [
        .init(red: 0, green: 205, blue: 205), nil, .init(red: 255, green: 175, blue: 95), nil,
    ])
}

@Test func extendedForegroundAndBackgroundResetIndependently() throws {
    let line = LogLine(level: .info, source: .engine,
                       text: "\u{1B}[38;2;1;2;3;104mимя\u{1B}[39m🙂\u{1B}[49m!")
    let segments = try #require(line.segments)
    let blue = LogLine.RGB(red: 92, green: 92, blue: 255)
    #expect(line.text == "имя🙂!")
    #expect(segments.map(\.foreground) == [.init(red: 1, green: 2, blue: 3), nil, nil])
    #expect(segments.map(\.background) == [blue, blue, nil])
}

@Test func redactionKeepsSafeColorsAndMasksSecretsSplitByColor() {
    var line = LogLine(level: .info, source: .engine, text: "\u{1B}[36mINFO\u{1B}[0m peer 1.2.3.4:443")
    line.redactText(secrets: [])
    #expect(line.text == "INFO peer x.x.x.x:•")
    #expect(line.segments?.first?.foreground != nil)
    #expect(line.segments?.map(\.text).joined() == line.text)

    var split = LogLine(level: .info, source: .engine, text: "key=abc\u{1B}[31mdef\u{1B}[0m")
    split.redactText(secrets: ["abcdef"])
    #expect(split.text == "key=•••")
    #expect(split.segments == nil)
}

@Test func redactsAddresses() {
    #expect(Redactor.redact("dial 1.2.3.4:56000 ok", secrets: []) == "dial x.x.x.x:• ok")
    #expect(Redactor.redact("peer 203.0.113.10 up", secrets: []) == "peer x.x.x.x up")
    #expect(Redactor.redact("via 2001:db8::1 done", secrets: []) == "via x:x done")
    #expect(Redactor.redact("to [2001:db8:0:0:0:0:0:1]:443", secrets: []) == "to [x:x]:•")
}

@Test func redactsLinksKeysAndSecrets() {
    #expect(Redactor.redact("-links https://vk.ru/call/join/AbC-123_x -n 12", secrets: []) == "-links ••• -n 12")
    #expect(Redactor.redact("-obf-key \(key64) -client-id \(id32)", secrets: []) == "-obf-key ••• -client-id •••")
    #expect(Redactor.redact("private_key=cHJpdmF0ZQ== ok", secrets: ["cHJpdmF0ZQ=="]) == "private_key=••• ok")
}

@Test func leavesOrdinaryTextAlone() {
    for text in ["12:34:56 started", "Free Turn Proxy client version=v4.1.5", "streams 3/12 connected",
                 "retry in 1.5s", "session=4e6db292 ok", "деление 10:30 и 1.2.3"] {
        #expect(Redactor.redact(text, secrets: ["", "ab"]) == text, "\(text)")
    }
}

// Командная строка запуска показывается всегда: ссылки и ключи в ней прячем даже без приватного режима.
@Test func secretsOnlyModeKeepsAddresses() {
    let line = "-peer 1.2.3.4:56000 -links https://vk.ru/call/join/x -obf-key \(key64)"
    #expect(Redactor.redact(line, secrets: [], maskAddresses: false) == "-peer 1.2.3.4:56000 -links ••• -obf-key •••")
}

@MainActor @Test func logStoreCapacityEvictsOldest() {
    let store = LogStore(capacity: 3)
    for i in 1...5 { store.append(LogLine(level: .info, source: .core, text: "l\(i)")) }
    #expect(store.lines.map(\.text) == ["l3", "l4", "l5"])
    #expect(Set(store.lines.map(\.id)).count == 3)
    store.clear()
    #expect(store.lines.isEmpty)
}

@Test func logFileRotatesAtLimit() throws {
    let dir = makeTempDir()
    let file = LogFile(directory: dir, maxBytes: 1000)
    let line = String(repeating: "x", count: 99)
    for _ in 0..<12 { file.append(line) }
    let current = dir.appendingPathComponent("session.log")
    let old = dir.appendingPathComponent("session.1.log")
    #expect(FileManager.default.fileExists(atPath: old.path))
    #expect(try Data(contentsOf: current).count <= 1000)
    #expect(try Data(contentsOf: current).count > 0)
}

@Test func logFileExportConcatenatesOldThenNew() throws {
    let dir = makeTempDir()
    let file = LogFile(directory: dir, maxBytes: 30)
    file.append("first line is long enough")
    file.append("second line is long too")
    file.append("third")
    let out = dir.appendingPathComponent("export.txt")
    try file.export(to: out)
    let text = try String(contentsOf: out, encoding: .utf8)
    let second = try #require(text.range(of: "second"))
    let third = try #require(text.range(of: "third"))
    #expect(second.lowerBound < third.lowerBound)
}

@Test func logFilesAre0600AndClearRemovesThem() throws {
    let dir = makeTempDir()
    let file = LogFile(directory: dir, maxBytes: 20)
    file.append("aaaaaaaaaaaaaaaaaaaaaaaaa")
    file.append("b")
    for name in ["session.log", "session.1.log"] {
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(name).path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600, "\(name)")
    }
    file.clear()
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
}
