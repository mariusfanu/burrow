import BurrowCore
import Foundation

/// Collects piped output from a background queue and tracks the latest full line.
final class LineOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var assembler = LineAssembler()
    private var lines: [String] = []
    private var latest = ""

    func append(_ chunk: Data) {
        lock.withLock {
            for line in assembler.feed(chunk) {
                lines.append(line.text)
                if !LogLine.isDecoration(line.text) {
                    latest = line.text
                }
            }
        }
    }

    func finish() -> [String] {
        lock.withLock {
            let tail = assembler.partial
            if !tail.isEmpty { lines.append(tail) }
            return lines
        }
    }

    var latestLine: String {
        lock.withLock { latest }
    }
}
