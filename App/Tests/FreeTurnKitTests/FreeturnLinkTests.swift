import Foundation
import Testing
@testable import FreeTurnKit

func b64Link(_ json: String) -> String {
    let b64 = Data(json.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "freeturn://" + b64
}

let goldenMinimal = "freeturn://eyJ2IjoxLCJwcm92aWRlciI6InZrIiwicGVlciI6IjEuMi4zLjQ6NTYwMDAifQ"
let hex64 = String(repeating: "ab12", count: 16)
let hex32 = String(repeating: "cd34", count: 8)

@Test func linkGoldenMinimal() throws {
    let link = try FreeturnLink.parse(goldenMinimal)
    #expect(link.provider == "vk")
    #expect(link.peer == "1.2.3.4:56000")
    #expect(link.wgConf == "")
    #expect(link.obfProfile == "")
    #expect(!link.bond)
}

@Test func linkAllFields() throws {
    let link = try FreeturnLink.parse(b64Link("""
    {"v":1,"provider":"direct","peer":"5.6.7.8:56001","transport":"udp","obf":"rtpopus3","key":"\(hex64)",
     "timing":20,"n":8,"spc":6,"cid":"\(hex32)","dns":"doh","dnss":"1.1.1.1,8.8.8.8","mcap":true,
     "name":"RU","vk":"https://vk.ru/call/join/x","wg":"[Interface]\\nPrivateKey = a\\n"}
    """))
    #expect(link.provider == "direct")
    #expect(link.peer == "5.6.7.8:56001")
    #expect(link.transport == "udp")
    #expect(link.obfProfile == "rtpopus3")
    #expect(link.obfKey == hex64)
    #expect(link.obfTimingMs == 20)
    #expect(link.n == 8)
    #expect(link.streamsPerCred == 6)
    #expect(link.clientId == hex32)
    #expect(link.dnsMode == "doh")
    #expect(link.dnsServers == "1.1.1.1,8.8.8.8")
    #expect(link.manualCaptcha)
    #expect(link.name == "RU")
    #expect(link.callLink == "https://vk.ru/call/join/x")
    #expect(link.wgConf == "[Interface]\nPrivateKey = a\n")
}

@Test func linkUnknownFieldsIgnored() throws {
    let link = try FreeturnLink.parse(b64Link(#"{"v":1,"provider":"vk","peer":"1.2.3.4:56000","zzz":{"a":1}}"#))
    #expect(link.peer == "1.2.3.4:56000")
}

// Ссылки приходят из мессенджеров: с пробелами, переводом строки, чужим регистром схемы и padding.
@Test func linkTolerantInput() throws {
    let payload = goldenMinimal.dropFirst("freeturn://".count)
    let link = try FreeturnLink.parse("  FREETURN://\(payload)==\n")
    #expect(link == (try FreeturnLink.parse(goldenMinimal)))
}

@Test func linkErrors() {
    #expect(throws: LinkError.invalidScheme) { try FreeturnLink.parse("http://x") }
    #expect(throws: LinkError.emptyPayload) { try FreeturnLink.parse("freeturn://") }
    #expect(throws: LinkError.badEncoding) { try FreeturnLink.parse("freeturn://!!!") }
    #expect(throws: LinkError.badEncoding) { try FreeturnLink.parse(b64Link("not json")) }
    #expect(throws: LinkError.unsupportedVersion) { try FreeturnLink.parse(b64Link(#"{"v":2,"provider":"vk","peer":"x"}"#)) }
    #expect(throws: LinkError.unsupportedVersion) { try FreeturnLink.parse(b64Link(#"{"provider":"vk","peer":"x"}"#)) }
    #expect(throws: LinkError.missingProvider) { try FreeturnLink.parse(b64Link(#"{"v":1,"peer":"x"}"#)) }
    #expect(throws: LinkError.missingPeer) { try FreeturnLink.parse(b64Link(#"{"v":1,"provider":"vk"}"#)) }
}

@Test func linkLooksLikeLink() {
    #expect(FreeturnLink.looksLikeLink("  FREETURN://abc "))
    #expect(!FreeturnLink.looksLikeLink("https://example.com"))
}

@Test func dnsListNormalize() {
    #expect(DnsList.normalize("1.1.1.1; bad!token 8.8.8.8") == "1.1.1.1,8.8.8.8")
    #expect(DnsList.normalize("  ") == "")
    #expect(DnsList.hasInvalidTokens("1.1.1.1 bad!token"))
    #expect(!DnsList.hasInvalidTokens("1.1.1.1, 2001:db8::1"))
}
