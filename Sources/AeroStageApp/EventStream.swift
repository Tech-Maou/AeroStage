import AeroStageCore
import Foundation

/// Keeps `aerospace subscribe --all` running and reports every event line.
/// If the process exits (e.g. AeroSpace quit), it is restarted with increasing delay.
@MainActor
final class EventStream {
    var onEvent: ((AeroEvent) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private let executable: String
    private var process: Process?
    private var stopped = true
    private var retryDelay: Duration = .milliseconds(500)

    init(executable: String) {
        self.executable = executable
    }

    func start() {
        stopped = false
        launch()
    }

    func stop() {
        stopped = true
        process?.terminate()
        process = nil
    }

    private func launch() {
        guard !stopped else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["subscribe", "--all"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let splitter = LineSplitter()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let events = splitter.append(chunk).compactMap(AeroEvent.decode(line:))
            guard !events.isEmpty else { return }
            Task { @MainActor in
                guard let self else { return }
                self.retryDelay = .milliseconds(500)
                self.onConnectionChange?(true)
                events.forEach { self.onEvent?($0) }
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.handleTermination() }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            handleTermination()
        }
    }

    private func handleTermination() {
        process = nil
        onConnectionChange?(false)
        guard !stopped else { return }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, .seconds(10))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.launch()
        }
    }
}

/// Splits a byte stream into lines. Only used from a pipe's readability handler.
private final class LineSplitter: @unchecked Sendable {
    private var buffer = Data()

    func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }
}
