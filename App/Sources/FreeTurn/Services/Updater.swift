import AppKit
import Darwin
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
    /// Обновление, которое ставится сейчас: пока не nil, открыто окно с прогрессом.
    private(set) var installing: AvailableUpdate?
    /// Скачано и всего байт (всего 0 - размер неизвестен).
    private(set) var received: Int64 = 0
    private(set) var expected: Int64 = 0
    @ObservationIgnored private var job: Task<Void, Never>?
    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    var available: AvailableUpdate? {
        if case let .available(update) = phase { return update }
        return nil
    }

    func check() async {
        guard phase != .checking, installing == nil else { return }
        phase = .checking
        var request = URLRequest(url: UpdateCheck.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard phase == .checking else { return }
            // 404 - в репозитории ещё нет релизов.
            if (response as? HTTPURLResponse)?.statusCode == 404 { phase = .upToDate; return }
            if let update = try UpdateCheck.available(from: data, current: currentVersion, arch: UpdateCheck.currentArch) {
                phase = .available(update)
            } else {
                phase = .upToDate
            }
        } catch {
            guard phase == .checking else { return }
            phase = .failed(L("Не удалось проверить обновления."))
        }
    }

    /// Запускает установку в фоне; окно прогресса следит за [installing].
    func start(_ update: AvailableUpdate, beforeQuit: @escaping () async -> Void) {
        guard installing == nil else { return }
        received = 0
        expected = 0
        phase = .downloading
        installing = update
        job = Task { await install(update, beforeQuit: beforeQuit) }
    }

    /// Отмена, пока идёт загрузка: обновление снова предлагается.
    func cancel() {
        guard phase == .downloading, let update = installing else { return }
        job?.cancel()
        job = nil
        installing = nil
        phase = .available(update)
    }

    /// Закрыть окно после ошибки.
    func dismissFailure() {
        installing = nil
    }

    /// Скачивает и ставит обновление; beforeQuit - отключить VPN перед выходом.
    private func install(_ update: AvailableUpdate, beforeQuit: @escaping () async -> Void) async {
        do {
            try Task.checkCancellation()
            let target = Bundle.main.bundleURL
            guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                throw UpdateError.message(L("Нет прав на запись в папку приложения. Скачайте DMG со страницы релиза."))
            }
            let dmg = try await download(update.dmgURL, progress: true)
            // Без контрольной суммы не ставим: DMG без подписи разработчика иначе ничем не проверить.
            guard let sumsURL = update.checksumsURL,
                  let sums = String(data: try Data(contentsOf: try await download(sumsURL)), encoding: .utf8),
                  let expected = UpdateCheck.checksum(for: update.dmgURL.lastPathComponent, in: sums),
                  try UpdateCheck.sha256(of: dmg) == expected
            else { throw UpdateError.message(L("Контрольная сумма обновления не совпала — установка отменена.")) }

            try Task.checkCancellation()
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
            // Открытый лист прогресса может заблокировать NSApplication.terminate.
            // VPN уже отключён, а установщик ждёт завершения этого процесса.
            exit(EXIT_SUCCESS)
        } catch is CancellationError {
            // Отменил пользователь: состояние уже вернул cancel().
        } catch let UpdateError.message(text) {
            phase = .failed(text)
        } catch {
            phase = .failed(L("Не удалось установить обновление: ") + error.localizedDescription)
        }
    }

    private enum UpdateError: Error { case message(String) }

    private func download(_ url: URL, progress: Bool = false) async throws -> URL {
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        let delegate = DownloadDelegate(destination: kept) { [weak self] done, total in
            guard progress else { return }
            Task { @MainActor in
                self?.received = done
                self?.expected = max(total, 0)
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    delegate.continuation = continuation
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw UpdateError.message(L("Не удалось скачать обновление."))
        }
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

/// Загрузка с прогрессом: файл переносится в [destination] до того, как система его удалит.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let onProgress: @Sendable (Int64, Int64) -> Void
    var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?

    init(destination: URL, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            moveError = URLError(.badServerResponse)
            return
        }
        do { try FileManager.default.moveItem(at: location, to: destination) } catch { moveError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error ?? moveError { continuation?.resume(throwing: error) } else { continuation?.resume() }
        continuation = nil
    }
}
