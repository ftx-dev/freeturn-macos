import Foundation
import Testing

private let appSources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/FreeTurn")

/// Все строки вида L("…") из исходников приложения.
private func usedKeys() throws -> Set<String> {
    let pattern = try NSRegularExpression(pattern: #"\bL\("((?:[^"\\]|\\.)*)"\)"#)
    var keys = Set<String>()
    let files = FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil)!
    for case let url as URL in files where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            keys.insert(String(text[Range(match.range(at: 1), in: text)!]).replacingOccurrences(of: #"\""#, with: "\""))
        }
    }
    return keys
}

private func englishTable() throws -> [String: String] {
    let url = appSources.appendingPathComponent("Resources/en.lproj/Localizable.strings")
    let table = try #require(NSDictionary(contentsOf: url) as? [String: String], "en.lproj/Localizable.strings не читается")
    return table
}

// Ключ строки - русский текст; без перевода английский интерфейс покажет его как есть.
@Test func everyUsedStringHasEnglishTranslation() throws {
    let missing = try usedKeys().subtracting(englishTable().keys).sorted()
    #expect(missing.isEmpty, "нет перевода: \(missing)")
}

@Test func noEmptyTranslations() throws {
    let empty = try englishTable().filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }.keys.sorted()
    #expect(empty.isEmpty, "пустой перевод: \(empty)")
}

@Test func noStaleTranslations() throws {
    let stale = try Set(englishTable().keys).subtracting(usedKeys()).sorted()
    #expect(stale.isEmpty, "перевод без строки в коде: \(stale)")
}

// %@ и %d должны совпадать в ключе и переводе, иначе String(format:) упадёт или соврёт.
@Test func formatSpecifiersMatch() throws {
    func specifiers(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: "%[@d]")
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }
    }
    for (key, value) in try englishTable() {
        #expect(specifiers(key) == specifiers(value), "разные подстановки: \(key)")
    }
}
