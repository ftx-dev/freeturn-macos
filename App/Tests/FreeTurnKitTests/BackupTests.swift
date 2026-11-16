import Foundation
import Testing
@testable import FreeTurnKit

// Известный вектор PBKDF2-HMAC-SHA256 ("password", "salt", 1 итерация): ключ выводится как у Android (BouncyCastle).
@Test func pbkdf2KnownVector() throws {
    let key = try BackupCrypto.deriveKey(password: "password", salt: Data("salt".utf8), iterations: 1)
    #expect(key.map { String(format: "%02x", $0) }.joined() == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
}

@Test func encryptDecryptRoundTrip() throws {
    let envelope = try BackupCrypto.encrypt(Data("секрет".utf8), password: "pass word")
    let o = try JSONSerialization.jsonObject(with: envelope) as! [String: Any]
    #expect(o["magic"] as? String == "freeturn-backup")
    #expect(o["v"] as? Int == 1)
    #expect(o["kdf"] as? String == "pbkdf2-sha256")
    #expect(o["iter"] as? Int == 210_000)
    #expect(Data(base64Encoded: o["salt"] as! String)?.count == 16)
    #expect(Data(base64Encoded: o["iv"] as! String)?.count == 12)
    // Как у Java GCM: шифротекст и 16-байтовый тег подряд.
    #expect(Data(base64Encoded: o["ct"] as! String)?.count == "секрет".utf8.count + 16)
    #expect(String(decoding: try BackupCrypto.decrypt(envelope, password: "pass word"), as: UTF8.self) == "секрет")
}

@Test func decryptErrors() throws {
    let envelope = try BackupCrypto.encrypt(Data("x".utf8), password: "a")
    #expect(throws: BackupError.badPassword) { try BackupCrypto.decrypt(envelope, password: "b") }
    #expect(throws: BackupError.badFormat) { try BackupCrypto.decrypt(Data("not json".utf8), password: "a") }
    #expect(throws: BackupError.badFormat) { try BackupCrypto.decrypt(Data(#"{"magic":"other"}"#.utf8), password: "a") }
    // Подсунутое число итераций не должно ни вешать приложение, ни ослаблять ключ.
    #expect(throws: BackupError.badFormat) {
        try BackupCrypto.decrypt(Data(#"{"magic":"freeturn-backup","v":1,"iter":1,"salt":"AA==","iv":"AA==","ct":"AA=="}"#.utf8), password: "a")
    }
    #expect(throws: BackupError.badFormat) {
        try BackupCrypto.decrypt(Data(#"{"magic":"freeturn-backup","v":1,"iter":100000000,"salt":"AA==","iv":"AA==","ct":"AA=="}"#.utf8), password: "a")
    }
}

@Test func payloadRoundTripKeepsMacData() throws {
    var s = Server(name: "A")
    s.client.serverAddress = "1.2.3.4:56000"
    let profile = RoutingProfile(name: "mine", defaultAction: .direct, rules: [RoutingRule(kind: .domain, value: "a.com", action: .vpn)])
    var settings = AppSettings()
    settings.privacyMode = true
    settings.autoConnect = true
    settings.theme = "dark"
    let data = BackupPayload(servers: ServersFile(list: [s], activeId: s.id), ownClientId: hex32,
                             routing: RoutingFile(profiles: [Presets.allViaVPN, profile], sharedProfileId: profile.id), settings: settings)
    let back = try BackupPayload.decode(data.encode())
    #expect(back.servers == data.servers)
    #expect(back.ownClientId == hex32)
    #expect(back.routing?.profiles.last == profile)
    #expect(back.settings.privacyMode)
    #expect(back.settings.autoConnect)
    #expect(back.settings.theme == "dark")
}

// Бэкап Android: формат v4, серверы в ServerJson, тема в themeMode. Маршрутов macOS в нём нет.
@Test func decodesAndroidBackup() throws {
    let json = #"""
    {"v":4,"servers":[{"id":"s1","name":"RU","ssh":{"ip":"1.2.3.4"},"client":{"serverAddress":"1.2.3.4:56000","provider":"direct","splitTunnelMode":"exclude"},"opts":{"obfProfile":"rtpopus3","obfKey":"k"}}],
     "activeId":"s1","ownClientId":"\#(hex32)","dynamicTheme":true,"nerdMode":true,"privacyMode":true,"seasonalDecor":true,
     "restartServerOnSwitch":false,"autoConnect":true,"hotspotProxy":false,"suppressUpdatePrompt":false,"suppressTgPrompt":true,"themeMode":"light","amoled":false}
    """#
    let p = try BackupPayload.decode(Data(json.utf8))
    #expect(p.servers.active?.client.provider == "direct")
    #expect(p.servers.list.count == 1)
    #expect(p.ownClientId == hex32)
    #expect(p.routing == nil)
    #expect(p.settings.privacyMode)
    #expect(p.settings.autoConnect)
    #expect(p.settings.theme == "light")
    #expect(p.settings.telegramPromptShown)
}

// Битый список серверов или чужой Client ID - отказ до того, как текущие данные затёрты.
@Test func payloadRejectsBadData() {
    #expect(throws: BackupError.badFormat) { try BackupPayload.decode(Data(#"{"v":4,"servers":"x","ownClientId":"\#(hex32)"}"#.utf8)) }
    #expect(throws: BackupError.badFormat) { try BackupPayload.decode(Data(#"{"v":4,"servers":[],"ownClientId":"short"}"#.utf8)) }
    #expect(throws: BackupError.badFormat) { try BackupPayload.decode(Data("[1]".utf8)) }
}

@Test func storeRestoresClientId() throws {
    let store = Store(directory: makeTempDir())
    _ = try store.ownClientId()
    try store.setOwnClientId(hex32)
    #expect(try store.ownClientId() == hex32)
    #expect(throws: (any Error).self) { try store.setOwnClientId("nope") }
}
