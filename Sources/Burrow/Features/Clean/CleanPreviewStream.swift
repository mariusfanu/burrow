import BurrowCore
import Foundation
import Synchronization

/// All decoding and parsing stays on one background queue. Only the newest coalesced
/// report waits for the main actor, regardless of how quickly the CLI prints.
final class CleanPreviewStream: @unchecked Sendable {
    let updates: AsyncStream<CleanReport>
    private let continuation: AsyncStream<CleanReport>.Continuation
    private let queue = DispatchQueue(label: "burrow.clean.preview", qos: .userInitiated)
    private var parser = CleanReportParser()
    private var scheduled = false
    private var isFinished = false
    private let cancelled = Mutex(false)
    private let pathListURL: URL
    private let originalList: FileStamp?

    private var isCancelled: Bool { cancelled.withLock { $0 } }

    init(pathListURL: URL) {
        self.pathListURL = pathListURL
        originalList = FileStamp(url: pathListURL)
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
    func finish() async -> CleanReport {
        await withCheckedContinuation { waiter in
            queue.async { [self] in
                guard !isCancelled else {
                    waiter.resume(returning: parser.snapshot)
                    return
                }
                var result = parser.finish()
                if parser.announcedPathList == pathListURL.path,
                   let beforeRead = FileStamp(url: pathListURL), beforeRead != originalList,
                   let paths = try? String(contentsOf: pathListURL, encoding: .utf8),
                   FileStamp(url: pathListURL) == beforeRead {
                    result = parser.finish(pathList: paths)
                } else if result.potentialBytes > 0 {
                    result.notes.append("Mole’s detailed file list wasn’t available for this preview.")
                }
                isFinished = true
                continuation.yield(result)
                continuation.finish()
                waiter.resume(returning: result)
            }
        }
    }

    private struct FileStamp: Equatable {
        let identity: TrashMover.FileIdentity
        let modified: Date
        let size: UInt64

        init?(url: URL) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let identity = TrashMover.FileIdentity(path: url.path),
                  let modified = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? NSNumber else { return nil }
            self.identity = identity
            self.modified = modified
            self.size = size.uint64Value
        }
    }

    func cancel() {
        cancelled.withLock { $0 = true }
        continuation.finish()
    }
}
