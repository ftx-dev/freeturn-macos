import Foundation

/// Дочерний процесс freeturn-core. Общение - строки JSON через stdin/stdout.
@MainActor
public final class CoreProcess: CoreControlling {
    public var onEvent: (@MainActor (CoreEvent) -> Void)?

    private let binary: URL
    private let stateDir: URL
    private var process: Process?
    private var input: FileHandle?

    public init(binary: URL, stateDir: URL) {
        self.binary = binary
        self.stateDir = stateDir
    }

    public func launch() throws {
        // Запись в трубу умершего ядра не должна убивать приложение сигналом.
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = binary
        process.arguments = ["-state-dir", stateDir.path]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let splitter = LineSplitter()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let events = splitter.feed(data).compactMap(CoreEvent.decode(line:))
            guard !events.isEmpty else { return }
            // Главная очередь сохраняет порядок событий.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { events.forEach { self?.onEvent?($0) } }
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onEvent?(.exited) }
            }
        }
        try process.run()
        self.process = process
        input = stdin.fileHandleForWriting
    }

    public func send(_ command: CoreCommand) {
        try? input?.write(contentsOf: Data((command.encoded() + "\n").utf8))
    }

    /// Закрытый stdin для ядра значит «приложение ушло»: оно останавливает сессию и выходит само.
    public func terminate() {
        try? input?.close()
        input = nil
        guard let process else { return }
        self.process = nil
        let stuck = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
            if stuck.isRunning { stuck.terminate() }
        }
    }
}
