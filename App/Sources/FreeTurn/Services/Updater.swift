import AppKit
import FreeTurnKit
import Observation

/// Автообновление из GitHub Releases: DMG своей архитектуры, проверка SHA-256 и бандла,
/// замена приложения после выхода и перезапуск.
@MainActor @Observable
final class Updater {
    enum Phase: Equatable {
        case idle, checking, upToDate, available(AvailableUpdate), downloading, installing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    var available: AvailableUpdate? {
        if case let .available(update) = phase { return update }
        return nil
    }

    func check() async {
        guard phase != .checking, phase != .downloading, phase != .installing else { return }
        phase = .checking
        var request = URLRequest(url: UpdateCheck.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            // 404 - в репозитории ещё нет релизов.
            if (response as? HTTPURLResponse)?.statusCode == 404 { phase = .upToDate; return }
            if let update = try UpdateCheck.available(from: data, current: currentVersion, arch: UpdateCheck.currentArch) {
                phase = .available(update)
            } else {
                phase = .upToDate
            }
        } catch {
            phase = .failed(L("Не удалось проверить обновления."))
        }
    }

    /// Скачивает и ставит обновление; beforeQuit - отключить VPN перед выходом.
    func install(_ update: AvailableUpdate, beforeQuit: @escaping () async -> Void) async {
        phase = .downloading
        do {
            let target = Bundle.main.bundleURL
            guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                throw UpdateError.message(L("Нет прав на запись в папку приложения. Скачайте DMG со страницы релиза."))
            }
            let dmg = try await download(update.dmgURL)
            // Без контрольной суммы не ставим: DMG без подписи разработчика иначе ничем не проверить.
            guard let sumsURL = update.checksumsURL,
                  let sums = String(data: try Data(contentsOf: try await download(sumsURL)), encoding: .utf8),
                  let expected = UpdateCheck.checksum(for: update.dmgURL.lastPathComponent, in: sums),
                  try UpdateCheck.sha256(of: dmg) == expected
            else { throw UpdateError.message(L("Контрольная сумма обновления не совпала — установка отменена.")) }

            phase = .installing
            let mount = FileManager.default.temporaryDirectory.appendingPathComponent("freeturn-update-\(UUID().uuidString)")
            try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
            let newApp = mount.appendingPathComponent("FreeTurn.app")
            do {
                try verify(newApp)
            } catch {
                try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
                throw error
            }
            try launchSwapScript(newApp: newApp, mount: mount, target: target)
            await beforeQuit()
            NSApp.terminate(nil)
        } catch let UpdateError.message(text) {
            phase = .failed(text)
        } catch {
            phase = .failed(L("Не удалось установить обновление: ") + error.localizedDescription)
        }
    }

    private enum UpdateError: Error { case message(String) }

    private func download(_ url: URL) async throws -> URL {
        let (file, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.message(L("Не удалось скачать обновление.")) }
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: file, to: kept)
        return kept
    }

    /// Внутри DMG должен быть FreeTurn нужной архитектуры с целой подписью.
    private func verify(_ app: URL) throws {
        guard let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateError.message(L("В обновлении не то приложение — установка отменена."))
        }
        let archs = try output("/usr/bin/lipo", ["-archs", app.appendingPathComponent("Contents/MacOS/FreeTurn").path])
        guard archs.split(separator: " ").contains(Substring(UpdateCheck.currentArch)) else {
            throw UpdateError.message(L("Обновление собрано под другой процессор — установка отменена."))
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }

    /// Приложение не может заменить себя, пока работает: замену делает скрипт после выхода.
    private func launchSwapScript(newApp: URL, mount: URL, target: URL) throws {
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
        rm -rf "$3.old" && mv "$3" "$3.old" && ditto "$1" "$3" && rm -rf "$3.old" || { rm -rf "$3"; mv "$3.old" "$3"; }
        hdiutil detach "$2" -force >/dev/null 2>&1
        open "$3"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script, "swap", newApp.path, mount.path, target.path]
        try process.run()
    }

    @discardableResult
    private func output(_ tool: String, _ args: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.message(String(format: L("Проверка обновления не прошла (%@)."), URL(fileURLWithPath: tool).lastPathComponent))
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(_ tool: String, _ args: [String]) throws { try output(tool, args) }
}
