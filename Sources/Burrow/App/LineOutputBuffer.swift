import BurrowCore
import Foundation
import Synchronization

/// Collects piped output from a background queue and tracks the latest full line.
final class LineOutputBuffer: Sendable {
    private struct State {
        var assembler = LineAssembler()
        var lines: [String] = []
        var latest = ""
    }

    private let state = Mutex(State())

    func append(_ chunk: Data) {
        state.withLock { state in
            for line in state.assembler.feed(chunk) {
                state.lines.append(line.text)
                if !LogLine.isDecoration(line.text) {
                    state.latest = line.text
                }
            }
        }
    }

    func finish() -> [String] {
        state.withLock { state in
            let tail = state.assembler.partial
            if !tail.isEmpty { state.lines.append(tail) }
            return state.lines
        }
    }

    var latestLine: String {
        state.withLock { $0.latest }
    }
}
