import BurrowCore
import Foundation

/// All decoding and parsing stays on one background queue. Only the newest coalesced
/// report waits for the main actor, regardless of how quickly the CLI prints.
final class CleanPreviewStream: @unchecked Sendable {
    let updates: AsyncStream<CleanReport>
    private let continuation: AsyncStream<CleanReport>.Continuation
    private let queue = DispatchQueue(label: "burrow.clean.preview", qos: .userInitiated)
    private var parser = CleanReportParser()
    private var scheduled = false
    private var isFinished = false
    private let cancellationLock = NSLock()
    private var cancelled = false

    private var isCancelled: Bool { cancellationLock.withLock { cancelled } }

    init() {
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func append(_ data: Data) {
        queue.async { [self] in
            guard !isFinished, !isCancelled else { return }
            parser.feed(data)
            guard !scheduled else { return }
            scheduled = true
            queue.asyncAfter(deadline: .now() + 0.12) { [self] in
                guard !isFinished, !isCancelled else { return }
                scheduled = false
                continuation.yield(parser.snapshot)
            }
        }
    }

    /// FIFO with appends, so completion includes every chunk and the unfinished tail.
    func finish(pathListURL: URL) async -> CleanReport {
        await withCheckedContinuation { waiter in
            queue.async { [self] in
                guard !isCancelled else {
                    waiter.resume(returning: parser.snapshot)
                    return
                }
                let paths = try? String(contentsOf: pathListURL, encoding: .utf8)
                let result = parser.finish(pathList: paths)
                isFinished = true
                continuation.yield(result)
                continuation.finish()
                waiter.resume(returning: result)
            }
        }
    }

    func cancel() {
        cancellationLock.withLock { cancelled = true }
        continuation.finish()
    }
}
