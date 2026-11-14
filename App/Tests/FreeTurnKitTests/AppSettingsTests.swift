import Foundation
import Testing
@testable import FreeTurnKit

private func decodeSettings(_ json: String) throws -> AppSettings {
    try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
}

@Test func captchaOpensInWindowByDefault() throws {
    #expect(AppSettings().captchaTarget == "window")
    #expect(try decodeSettings("{}").captchaTarget == "window")
}

@Test func captchaTargetBrowserIsKept() throws {
    #expect(try decodeSettings(#"{"captchaTarget":"browser"}"#).captchaTarget == "browser")
}

@Test func unknownCaptchaTargetFallsBackToWindow() throws {
    #expect(try decodeSettings(#"{"captchaTarget":"popup"}"#).captchaTarget == "window")
}

@Test func unknownTunStackFallsBackToMixed() throws {
    #expect(try decodeSettings(#"{"tunStack":"lwip"}"#).tunStack == "mixed")
}
