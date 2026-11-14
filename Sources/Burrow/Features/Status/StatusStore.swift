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
    private var freshnessTask: Task<Void, Never>?
    private let freshnessClock: any Clock<Duration>
    private(set) var hasFreshSample = false
    private let commands: CommandClient
    private let retryDelay: Duration
    private let gpuReadings: @Sendable () -> [GPUReading]
    private(set) var isRunning = false

    /// Counts samples, which starts each chart's scroll and pulses the live indicator.
    private(set) var sampleCount = 0
    private let historyLimit = 60

    init(
        commands: CommandClient = CommandClient(),
        retryDelay: Duration = .seconds(3),
        freshnessClock: any Clock<Duration> = ContinuousClock(),
        gpuReadings: @escaping @Sendable () -> [GPUReading] = GPUStatistics.read
    ) {
        self.commands = commands
        self.retryDelay = retryDelay
        self.gpuReadings = gpuReadings
        self.freshnessClock = freshnessClock
    }

    isolated deinit {
        task?.cancel()
        freshnessTask?.cancel()
    }

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
                    self.clearFreshness()
                }
            }
            // Three failures in a row end the stream. A process that worked and later exited
            // starts the count again, so hours of good samples don't use up the attempts.
            var failures = 0
            while failures < 3 {
                guard !Task.isCancelled else { return }
                let (events, continuation) = AsyncStream<SampleEvent>.makeStream()
                async let exit = Self.readSamples(
                    cli: cli, interval: interval, commands: commands,
                    gpuReadings: gpuReadings, into: continuation
                )
                var deliveredSample = false
                for await event in events {
                    guard !Task.isCancelled, self?.streamID == id else { return }
                    switch event {
                    case .sample(let snapshot):
                        deliveredSample = true
                        self?.ingest(snapshot)
                        self?.markFresh(interval: interval)
                    case .unreadable:
                        self?.errorMessage = "Mole’s status output couldn’t be read. A different version of Mole may have changed its format."
                    }
                }
                do {
                    let status = try await exit
                    guard !Task.isCancelled, self?.streamID == id else { return }
                    self?.errorMessage = "The status stream stopped (status \(status)). Retrying…"
                } catch {
                    guard !Task.isCancelled, self?.streamID == id else { return }
                    self?.errorMessage = error.localizedDescription
                }
                self?.clearFreshness()
                failures = deliveredSample ? 1 : failures + 1
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
        clearFreshness()
    }

    private enum SampleEvent: Sendable {
        case sample(StatusSnapshot)
        case unreadable
    }

    private nonisolated static func readSamples(
        cli: CLIInfo, interval: Int, commands: CommandClient,
        gpuReadings: @escaping @Sendable () -> [GPUReading],
        into events: AsyncStream<SampleEvent>.Continuation
    ) async throws -> Int32 {
        defer { events.finish() }
        let parser = NDJSONParser()
        return try await commands.stream(cli.executable, ["status", "--watch", "--interval", "\(interval)s"]) { chunk in
            let snapshots = parser.feed(chunk)
            let rejectedLines = parser.takeRejectedLines()
            if snapshots.isEmpty, rejectedLines > 0 { events.yield(.unreadable) }
            for snapshot in snapshots {
                events.yield(.sample(snapshot.fillingMissingGPUUsage(from: gpuReadings)))
            }
        }
    }

    private func markFresh(interval: Int) {
        freshnessTask?.cancel()
        hasFreshSample = true
        let clock = freshnessClock
        freshnessTask = Task { [weak self] in
            try? await clock.sleep(for: .seconds(max(1, interval)) * 3)
            guard !Task.isCancelled else { return }
            self?.hasFreshSample = false
        }
    }

    private func clearFreshness() {
        freshnessTask?.cancel()
        freshnessTask = nil
        hasFreshSample = false
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
