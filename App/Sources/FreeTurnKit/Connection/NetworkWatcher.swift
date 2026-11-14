import Foundation
import Network

/// Следит за сменой физической сети. Событий при одной смене приходит несколько -
/// сообщаем один раз, когда они стихнут.
@MainActor
public final class NetworkWatcher: NetworkWatching {
    public var onChange: (@MainActor (NetworkSnapshot?) -> Void)?

    private var monitor: NWPathMonitor?
    private var pending: DispatchWorkItem?

    public init() {}

    public func current() -> NetworkSnapshot? { SystemNetwork.current() }

    public func start() {
        stop()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.schedule() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.freeturn.network"))
        self.monitor = monitor
    }

    public func stop() {
        monitor?.cancel()
        monitor = nil
        pending?.cancel()
        pending = nil
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange?(SystemNetwork.current()) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}
