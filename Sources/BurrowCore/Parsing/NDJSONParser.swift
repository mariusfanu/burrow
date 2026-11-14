import Foundation
import Synchronization

/// Splits newline-delimited JSON from a background queue.
public final class NDJSONParser: Sendable {
    private struct State {
        var buffer = Data()
        var rejectedLines = 0
        var discardsUntilNewline = false
        let decoder = JSONDecoder.forCLI()
    }

    private let state = Mutex(State())
    private let maximumLineBytes: Int

    public init() { maximumLineBytes = 4 * 1024 * 1024 }

    init(maximumLineBytes: Int) { self.maximumLineBytes = maximumLineBytes }

    /// How many complete lines weren't a snapshot since the last time this was asked.
    public func takeRejectedLines() -> Int {
        state.withLock { state in
            defer { state.rejectedLines = 0 }
            return state.rejectedLines
        }
    }

    public func feed(_ chunk: Data) -> [StatusSnapshot] {
        state.withLock { state in
            var snapshots: [StatusSnapshot] = []
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let newline = chunk[start...].firstIndex(of: 0x0A)
                let part = chunk[start..<(newline ?? chunk.endIndex)]
                if state.buffer.isEmpty, !state.discardsUntilNewline, let newline {
                    if part.count > maximumLineBytes {
                        state.rejectedLines += 1
                    } else if !part.isEmpty {
                        if let snapshot = try? StatusSnapshot.decode(part, using: state.decoder), snapshot.containsReadings {
                            snapshots.append(snapshot)
                        } else {
                            state.rejectedLines += 1
                        }
                    }
                    state.discardsUntilNewline = false
                    start = chunk.index(after: newline)
                    continue
                }
                if !state.discardsUntilNewline {
                    if part.count > maximumLineBytes - state.buffer.count {
                        state.buffer.removeAll()
                        state.rejectedLines += 1
                        state.discardsUntilNewline = true
                    } else {
                        state.buffer.append(part)
                    }
                }
                guard let newline else { break }
                if !state.buffer.isEmpty {
                    if let snapshot = try? StatusSnapshot.decode(state.buffer, using: state.decoder), snapshot.containsReadings {
                        snapshots.append(snapshot)
                    } else {
                        state.rejectedLines += 1
                    }
                    state.buffer.removeAll(keepingCapacity: true)
                }
                state.discardsUntilNewline = false
                start = chunk.index(after: newline)
            }
            return snapshots
        }
    }
}
