import AppKit

public struct AppEntry: Identifiable, Hashable, Sendable {
    /// Путь к бандлу .app.
    public var id: String
    public var name: String
    public var isRunning: Bool
}

@MainActor public enum InstalledApps {
    /// Приложения из стандартных каталогов плюс запущенные; запущенные - первыми.
    public static func list() -> [AppEntry] {
        let fm = FileManager.default
        let running = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.bundleURL?.path })
        var paths = running
        let home = fm.homeDirectoryForCurrentUser.path
        for dir in ["/Applications", "/Applications/Utilities", "/System/Applications", home + "/Applications"] {
            for item in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where item.hasSuffix(".app") {
                paths.insert(dir + "/" + item)
            }
        }
        return paths
            .map { AppEntry(id: $0, name: fm.displayName(atPath: $0).replacingOccurrences(of: ".app", with: ""),
                            isRunning: running.contains($0)) }
            .sorted { ($0.isRunning ? 0 : 1, $0.name.lowercased()) < ($1.isRunning ? 0 : 1, $1.name.lowercased()) }
    }
}
