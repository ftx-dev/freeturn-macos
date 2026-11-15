import AppKit

/// Сообщает, сколько машина проспала: после долгого сна аллокации реле протухают.
@MainActor
final class SleepWatcher {
    private var sleptAt: Date?
    private var observers: [NSObjectProtocol] = []

    init(onWake: @escaping @MainActor (TimeInterval) -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleptAt = Date() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let sleptAt = self.sleptAt else { return }
                self.sleptAt = nil
                onWake(Date().timeIntervalSince(sleptAt))
            }
        })
    }
}
