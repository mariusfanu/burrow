import Foundation

/// Splits newline-delimited JSON from a background queue.
public final class NDJSONParser: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var rejectedLines = 0

    public init() {}

    /// How many complete lines weren't a snapshot since the last time this was asked.
    public func takeRejectedLines() -> Int {
        lock.withLock {
            defer { rejectedLines = 0 }
            return rejectedLines
        }
    }

    public func feed(_ chunk: Data) -> [StatusSnapshot] {
        lock.withLock {
            buffer.append(chunk)
            var snapshots: [StatusSnapshot] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let snapshot = try? StatusSnapshot.decode(Data(line)) {
                    snapshots.append(snapshot)
                } else if !line.isEmpty {
                    rejectedLines += 1
                }
            }
            return snapshots
        }
    }
}
