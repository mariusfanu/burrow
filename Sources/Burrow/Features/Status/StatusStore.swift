import BurrowCore
import Foundation
import Observation

/// Follows `mo status --watch` and keeps a short history for the charts.
@MainActor
@Observable
final class StatusStore {
    private(set) var snapshot: StatusSnapshot?
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var downloadHistory: [Double] = []
    private(set) var errorMessage: String?

    private var task: Task<Void, Never>?
    private var currentInterval = 0
    private var currentCLI: CLIInfo?
    private var streamID = UUID()
    private var sampleSourceID = UUID()
    /// Whether the current process has produced a sample, which clears its failed attempts.
    private var sourceDeliveredSample = false
    private let commands: CommandClient
    private let retryDelay: Duration
    private let gpuReadings: @Sendable () -> [GPUReading]
    private(set) var isRunning = false

    init(
        commands: CommandClient = CommandClient(),
        retryDelay: Duration = .seconds(3),
        gpuReadings: @escaping @Sendable () -> [GPUReading] = GPUStatistics.read
    ) {
        self.commands = commands
        self.retryDelay = retryDelay
        self.gpuReadings = gpuReadings
    }
    /// Counts samples, which starts each chart's scroll and pulses the live indicator.
    private(set) var sampleCount = 0
    private let historyLimit = 60

    /// Restarts when the interval or CLI changes, or the previous stream has finished.
    func start(cli: CLIInfo, interval: Int) {
        guard task == nil || interval != currentInterval || cli != currentCLI else { return }
        stop()
        let id = UUID()
        streamID = id
        currentInterval = interval
        currentCLI = cli
        errorMessage = nil
        isRunning = true
        let commands = commands
        let retryDelay = retryDelay
        let gpuReadings = gpuReadings
        task = Task { [weak self] in
            defer {
                if let self, self.streamID == id {
                    self.task = nil
                    self.isRunning = false
                }
            }
            // Three failures in a row end the stream. A process that worked and later exited
            // starts the count again, so hours of good samples don't use up the attempts.
            var failures = 0
            while failures < 3 {
                guard !Task.isCancelled else { return }
                let sourceID = UUID()
                self?.sampleSourceID = sourceID
                self?.sourceDeliveredSample = false
                let sink: @MainActor @Sendable (StatusSnapshot) -> Void = { [weak self] snapshot in
                    guard let self, self.streamID == id, self.sampleSourceID == sourceID, self.isRunning else { return }
                    self.sourceDeliveredSample = true
                    self.ingest(snapshot)
                }
                let unreadable: @MainActor @Sendable () -> Void = { [weak self] in
                    guard let self, self.streamID == id, self.sampleSourceID == sourceID else { return }
                    self.errorMessage = "Mole’s status output couldn’t be read. A different version of Mole may have changed its format."
                }
                // A truncated JSON line from a failed process must not contaminate its replacement.
                let parser = NDJSONParser()
                do {
                    let status = try await commands.stream(
                        cli.executable, ["status", "--watch", "--interval", "\(interval)s"], { chunk in
                            let snapshots = parser.feed(chunk)
                            let rejectedLines = parser.takeRejectedLines()
                            if snapshots.isEmpty, rejectedLines > 0 {
                                Task { @MainActor in unreadable() }
                            }
                            for snapshot in snapshots {
                                let snapshot = snapshot.fillingMissingGPUUsage(from: gpuReadings)
                                Task { @MainActor in sink(snapshot) }
                            }
                        }
                    )
                    guard !Task.isCancelled, self?.streamID == id else { return }
                    self?.errorMessage = "The status stream stopped (status \(status)). Retrying…"
                } catch {
                    guard !Task.isCancelled, self?.streamID == id else { return }
                    self?.errorMessage = error.localizedDescription
                }
                await Task.yield()
                failures = self?.sourceDeliveredSample == true ? 1 : failures + 1
                if failures < 3 { try? await Task.sleep(for: retryDelay) }
            }
            if !Task.isCancelled, self?.streamID == id {
                self?.errorMessage = "Live status isn't available right now."
            }
        }
    }

    func retry(cli: CLIInfo) {
        let interval = currentInterval > 0 ? currentInterval : 2
        stop()
        start(cli: cli, interval: interval)
    }

    func stop() {
        streamID = UUID()
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func ingest(_ snapshot: StatusSnapshot) {
        var snapshot = snapshot
        // A sample without a process list, such as the first one after the stream resumes,
        // keeps the last list rather than blinking the table empty for a tick.
        if snapshot.topProcesses?.isEmpty ?? true, let previous = self.snapshot?.topProcesses, !previous.isEmpty {
            snapshot.topProcesses = previous
        }
        self.snapshot = snapshot
        errorMessage = nil
        sampleCount += 1
        append(snapshot.cpu?.usage ?? 0, to: &cpuHistory)
        append(snapshot.memory?.usedPercent ?? 0, to: &memoryHistory)
        append(snapshot.totalDownload, to: &downloadHistory)
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
    }
}
