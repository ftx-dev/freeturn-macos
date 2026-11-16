import Foundation
import Testing
@testable import FreeTurnKit

private func release(tag: String = "v0.2.0", draft: Bool = false, prerelease: Bool = false,
                     assets: [String] = ["FreeTurn-0.2.0-arm64.dmg", "FreeTurn-0.2.0-x86_64.dmg", "SHA256SUMS.txt"]) -> Data {
    let list = assets.map { #"{"name":"\#($0)","browser_download_url":"https://github.com/o/r/releases/download/\#(tag)/\#($0)","size":100}"# }
    return Data(#"{"tag_name":"\#(tag)","draft":\#(draft),"prerelease":\#(prerelease),"html_url":"https://github.com/o/r/releases/tag/\#(tag)","body":"Что нового","assets":[\#(list.joined(separator: ","))]}"#.utf8)
}

@Test func versionComparison() {
    #expect(AppVersion("0.2.0") > AppVersion("0.1.0"))
    #expect(AppVersion("v0.10.0") > AppVersion("0.9.9"))
    #expect(AppVersion("1.0") == AppVersion("1.0.0"))
    #expect(!(AppVersion("0.1.0") > AppVersion("0.1.0")))
    #expect(AppVersion("0.1.1") > AppVersion("0.1"))
}

// DMG выбирается строго под свою архитектуру: приложение под Intel на Apple Silicon - и наоборот - ставить нельзя.
@Test(arguments: [("arm64", "FreeTurn-0.2.0-arm64.dmg"), ("x86_64", "FreeTurn-0.2.0-x86_64.dmg")])
func picksDmgForArchitecture(arch: String, expected: String) throws {
    let update = try #require(try UpdateCheck.available(from: release(), current: "0.1.0", arch: arch))
    #expect(update.version == "0.2.0")
    #expect(update.dmgURL.lastPathComponent == expected)
    #expect(update.checksumsURL?.lastPathComponent == "SHA256SUMS.txt")
    #expect(update.notes == "Что нового")
}

@Test func noUpdateWhenSameOrOlder() throws {
    #expect(try UpdateCheck.available(from: release(tag: "v0.1.0"), current: "0.1.0", arch: "arm64") == nil)
    #expect(try UpdateCheck.available(from: release(tag: "v0.0.9"), current: "0.1.0", arch: "arm64") == nil)
}

@Test func skipsDraftsPrereleasesAndMissingArch() throws {
    #expect(try UpdateCheck.available(from: release(draft: true), current: "0.1.0", arch: "arm64") == nil)
    #expect(try UpdateCheck.available(from: release(prerelease: true), current: "0.1.0", arch: "arm64") == nil)
    #expect(try UpdateCheck.available(from: release(assets: ["FreeTurn-0.2.0-x86_64.dmg"]), current: "0.1.0", arch: "arm64") == nil)
}

// Ссылка на скачивание берётся только с github.com: подменённый ответ не уведёт на чужой хост.
@Test func rejectsForeignDownloadHost() throws {
    let json = #"{"tag_name":"v0.2.0","draft":false,"prerelease":false,"html_url":"","body":"","assets":[{"name":"FreeTurn-0.2.0-arm64.dmg","browser_download_url":"https://evil.example/x.dmg"}]}"#
    #expect(try UpdateCheck.available(from: Data(json.utf8), current: "0.1.0", arch: "arm64") == nil)
}

@Test func badJsonThrows() {
    #expect(throws: (any Error).self) { try UpdateCheck.available(from: Data("nope".utf8), current: "0.1.0", arch: "arm64") }
}

@Test func checksumLookup() {
    let sums = """
    \(String(repeating: "a", count: 64))  FreeTurn-0.2.0-arm64.dmg
    \(String(repeating: "b", count: 64))  FreeTurn-0.2.0-x86_64.dmg
    """
    #expect(UpdateCheck.checksum(for: "FreeTurn-0.2.0-x86_64.dmg", in: sums) == String(repeating: "b", count: 64))
    #expect(UpdateCheck.checksum(for: "missing.dmg", in: sums) == nil)
}

@Test func sha256OfFile() throws {
    let url = makeTempDir().appendingPathComponent("f")
    try Data("abc".utf8).write(to: url)
    #expect(try UpdateCheck.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}
