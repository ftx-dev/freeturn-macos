import CommonCrypto
import CryptoKit
import Foundation

public enum BackupError: Error, Equatable {
    case badFormat, badPassword
}

/// Шифрование бэкапа паролем - формат Android-клиента (BackupCrypto): PBKDF2-SHA256 + AES-256-GCM,
/// конверт - JSON с base64-полями. Файлы читаются обоими клиентами.
public enum BackupCrypto {
    static let magic = "freeturn-backup"
    static let iterations = 210_000
    static let iterationRange = 100_000...2_000_000

    public static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        let salt = random(16)
        let iv = random(12)
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: iv))
        let envelope: [String: Any] = [
            "magic": magic, "v": 1, "kdf": "pbkdf2-sha256", "iter": iterations,
            "salt": salt.base64EncodedString(), "iv": iv.base64EncodedString(),
            // Как у Java AES/GCM: шифротекст и тег подряд.
            "ct": (box.ciphertext + box.tag).base64EncodedString(),
        ]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    public static func decrypt(_ envelope: Data, password: String) throws -> Data {
        guard let o = try? JSONSerialization.jsonObject(with: envelope) as? [String: Any],
              o["magic"] as? String == magic else { throw BackupError.badFormat }
        let iter = o["iter"] as? Int ?? iterations
        // Чужое число итераций не должно ни вешать приложение, ни ослаблять ключ.
        guard iterationRange.contains(iter),
              let salt = (o["salt"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let iv = (o["iv"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let ct = (o["ct"] as? String).flatMap({ Data(base64Encoded: $0) }),
              ct.count >= 16, let nonce = try? AES.GCM.Nonce(data: iv)
        else { throw BackupError.badFormat }
        let key = try deriveKey(password: password, salt: salt, iterations: iter)
        do {
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct.dropLast(16), tag: ct.suffix(16))
            return try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            // Не сошёлся тег GCM - неверный пароль (или подменённый файл).
            throw BackupError.badPassword
        }
    }

    static func deriveKey(password: String, salt: Data, iterations: Int) throws -> Data {
        var key = Data(count: 32)
        let pass = Array(password.utf8)
        let status = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.map { CChar(bitPattern: $0) }, pass.count,
                                     saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                     keyBytes.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        guard status == kCCSuccess else { throw BackupError.badFormat }
        return key
    }

    private static func random(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
    }
}

/// Содержимое бэкапа - формат Android v4 (SettingsBackup) плюс поле macRouting с профилями маршрутов.
/// Android лишнее поле игнорирует, а его серверы читаются здесь как есть.
public struct BackupPayload: Equatable, Sendable {
    public var servers: ServersFile
    public var ownClientId: String
    /// nil - бэкап Android: маршрутов в нём нет, текущие остаются.
    public var routing: RoutingFile?
    public var settings: AppSettings

    public init(servers: ServersFile, ownClientId: String, routing: RoutingFile?, settings: AppSettings) {
        self.servers = servers
        self.ownClientId = ownClientId
        self.routing = routing
        self.settings = settings
    }

    public func encode() throws -> Data {
        let serversJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(servers.list))
        let routingJSON = try routing.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
        var o: [String: Any] = [
            "v": 4, "servers": serversJSON, "ownClientId": ownClientId,
            "privacyMode": settings.privacyMode, "autoConnect": settings.autoConnect,
            "suppressTgPrompt": settings.telegramPromptShown, "themeMode": settings.theme,
            // Поля Android, у которых на macOS нет пары, - с их значениями по умолчанию.
            "dynamicTheme": true, "nerdMode": settings.debugScreen, "seasonalDecor": true, "restartServerOnSwitch": false,
            "hotspotProxy": false, "suppressUpdatePrompt": !settings.checkUpdates, "amoled": settings.appIcon != "standard",
        ]
        if let id = servers.activeId { o["activeId"] = id }
        if let routingJSON { o["macRouting"] = routingJSON }
        return try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])
    }

    public static func decode(_ data: Data) throws -> BackupPayload {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = o["servers"] as? [Any],
              let servers = try? JSONDecoder().decode([Server].self, from: JSONSerialization.data(withJSONObject: list))
        else { throw BackupError.badFormat }
        // Без верного Client ID сервер не пустит восстановленные профили: проверяем до затирания данных.
        guard let cid = o["ownClientId"] as? String, cid.count == 32, cid.allSatisfy(\.isHexDigit) else { throw BackupError.badFormat }
        let routing = (o["macRouting"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { try? JSONDecoder().decode(RoutingFile.self, from: $0) }?.normalized()
        var settings = AppSettings()
        settings.privacyMode = o["privacyMode"] as? Bool ?? false
        settings.autoConnect = o["autoConnect"] as? Bool ?? false
        settings.telegramPromptShown = o["suppressTgPrompt"] as? Bool ?? false
        settings.debugScreen = o["nerdMode"] as? Bool ?? false
        settings.checkUpdates = !(o["suppressUpdatePrompt"] as? Bool ?? false)
        if let theme = o["themeMode"] as? String, ["system", "light", "dark"].contains(theme) { settings.theme = theme }
        let activeId = (o["activeId"] as? String).flatMap { id in servers.contains { $0.id == id } ? id : nil } ?? servers.first?.id
        return BackupPayload(servers: ServersFile(list: servers, activeId: activeId), ownClientId: cid.lowercased(),
                             routing: routing, settings: settings)
    }
}
