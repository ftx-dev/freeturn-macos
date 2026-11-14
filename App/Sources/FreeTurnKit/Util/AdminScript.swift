import Foundation

/// Команды AppleScript для установки и удаления службы с правами администратора.
/// Путь к приложению выбирает пользователь (и может выбрать злоумышленник), поэтому он
/// экранируется дважды: для shell и для строки AppleScript.
public enum AdminScript {
    public static func install(daemonDir: String, uid: UInt32) -> String {
        wrap("\(shellQuote(daemonDir + "/install-daemon.sh")) \(shellQuote(daemonDir)) \(uid)")
    }

    public static func uninstall(daemonDir: String) -> String {
        wrap(shellQuote(daemonDir + "/uninstall-daemon.sh"))
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private static func wrap(_ command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }
}
