import Foundation
import FreeTurnKit

enum DaemonInstallError: Error {
    case cancelled
    case failed(String)
}

/// Ставит и удаляет службу через системный запрос пароля администратора.
enum DaemonInstaller {
    private static var daemonDir: String {
        (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("daemon").path
    }

    static func install() async throws {
        try await run(AdminScript.install(daemonDir: daemonDir, uid: getuid()))
        // Служба стартует не мгновенно: ждём сокет.
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: DaemonProtocol.socketPath) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    static func uninstall() async throws {
        try await run(AdminScript.uninstall(daemonDir: daemonDir))
    }

    private static func run(_ script: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stderr = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                process.standardError = stderr
                process.standardOutput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: DaemonInstallError.failed("\(error.localizedDescription)"))
                    return
                }
                let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else if message.contains("-128") {
                    // Пользователь закрыл окно пароля.
                    continuation.resume(throwing: DaemonInstallError.cancelled)
                } else {
                    continuation.resume(throwing: DaemonInstallError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
        }
    }
}
