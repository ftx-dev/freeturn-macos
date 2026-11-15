import Foundation
import Observation

/// Лог на экране: последние строки в памяти.
@MainActor @Observable
public final class LogStore {
    public private(set) var lines: [LogLine] = []
    @ObservationIgnored private let capacity: Int
    @ObservationIgnored private var nextId = 0

    public init(capacity: Int = 5000) {
        self.capacity = capacity
    }

    public func append(_ line: LogLine) {
        var line = line
        nextId += 1
        line.id = nextId
        lines.append(line)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }

    public func clear() {
        lines.removeAll()
    }
}
