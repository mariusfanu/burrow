import Foundation
import Synchronization

/// Splits newline-delimited JSON from a background queue.
public final class NDJSONParser: Sendable {
    private struct State {
        var buffer = Data()
        var rejectedLines = 0
    }

    private let state = Mutex(State())

    public init() {}

    /// How many complete lines weren't a snapshot since the last time this was asked.
    public func takeRejectedLines() -> Int {
        state.withLock { state in
            defer { state.rejectedLines = 0 }
            return state.rejectedLines
        }
    }

    public func feed(_ chunk: Data) -> [StatusSnapshot] {
        state.withLock { state in
            state.buffer.append(chunk)
            var snapshots: [StatusSnapshot] = []
            while let newline = state.buffer.firstIndex(of: 0x0A) {
                let line = state.buffer[state.buffer.startIndex..<newline]
                state.buffer.removeSubrange(state.buffer.startIndex...newline)
                if let snapshot = try? StatusSnapshot.decode(Data(line)) {
                    snapshots.append(snapshot)
                } else if !line.isEmpty {
                    state.rejectedLines += 1
                }
            }
            return snapshots
        }
    }
}
