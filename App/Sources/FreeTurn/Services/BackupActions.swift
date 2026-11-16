import AppKit
import FreeTurnKit
import UniformTypeIdentifiers

/// Резервная копия под паролем - формат Android-клиента: файлы читаются обоими клиентами.
extension AppModel {
    func exportBackup(password: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "freeturnx-backup-\(Date().formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let payload = BackupPayload(servers: servers, ownClientId: try store.ownClientId(), routing: routing, settings: settings)
            try BackupCrypto.encrypt(payload.encode(), password: password).write(to: url, options: .atomic)
            backupMessage = L("Настройки экспортированы")
        } catch {
            backupMessage = L("Не удалось сохранить файл")
        }
    }

    func chooseBackupFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .data]
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Восстановление заменяет серверы, Client ID устройства и часть настроек; маршруты - если они есть в файле.
    func restoreBackup(from url: URL, password: String) async -> Bool {
        let payload: BackupPayload
        do {
            payload = try BackupPayload.decode(BackupCrypto.decrypt(Data(contentsOf: url), password: password))
        } catch BackupError.badPassword {
            backupMessage = L("Неверный пароль")
            return false
        } catch {
            backupMessage = L("Неверный формат файла")
            return false
        }
        await connection.disconnect()
        do { try store.setOwnClientId(payload.ownClientId) } catch {
            backupMessage = L("Не удалось восстановить")
            return false
        }
        servers = payload.servers
        if let restored = payload.routing { routing = restored }
        settings.privacyMode = payload.settings.privacyMode
        settings.autoConnect = payload.settings.autoConnect
        settings.theme = payload.settings.theme
        settings.telegramPromptShown = settings.telegramPromptShown || payload.settings.telegramPromptShown
        settings.wasConnected = false
        persist()
        backupMessage = String(format: L("Восстановлено серверов: %d"), servers.list.count)
        section = .servers
        return true
    }
}
