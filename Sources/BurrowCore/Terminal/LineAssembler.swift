import Foundation

/// Turns a raw terminal stream into finished lines of plain text.
///
/// Carriage-return redraws such as spinners overwrite the pending line and never
/// reach the output, while the text still pending is exposed as `partial` so a
/// caller can show activity and recognize prompts that end without a newline.
public struct LineAssembler: Sendable {
    private var tokenizer = EscapeTokenizer()
    private var pending: [UInt8] = []
    private var cursorResetPending = false
    private let maximumPendingBytes: Int
    private(set) public var inAlternateScreen = false

    public init(maximumPendingBytes: Int = 4 * 1024 * 1024) {
        self.maximumPendingBytes = max(maximumPendingBytes, 1)
    }

    /// The text on the unfinished line.
    public var partial: String {
        String(decoding: pending, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    /// The unfinished line with its leading indentation intact, for parsers whose
    /// grammar distinguishes report rows from unindented closing text.
    public var partialLine: String {
        String(decoding: pending, as: UTF8.self).droppingTrailingWhitespace
    }

    /// Consumes bytes and returns the lines they completed.
    public mutating func feed(_ data: Data) -> [AssembledLine] {
        var finished: [AssembledLine] = []
        data.withUnsafeBytes { bytes in
            for byte in bytes {
                switch tokenizer.next(byte) {
                case .text(let text):
                    consumeText(text, into: &finished)
                case .csi(let final):
                    finishCSI(final: final)
                case nil, .escape, .osc, .ignored:
                    break
                }
            }
        }
        return finished
    }

    private mutating func consumeText(_ byte: UInt8, into finished: inout [AssembledLine]) {
        switch byte {
        case 0x0A:
            cursorResetPending = false
            emit(into: &finished)
        case 0x0D:
            cursorResetPending = true
        case 0x08:
            if !pending.isEmpty { pending.removeLast() }
        case 0x09:
            appendPrintable(0x20)
        case 0x00..<0x20, 0x7F:
            break
        default:
            appendPrintable(byte)
        }
    }

    private mutating func appendPrintable(_ byte: UInt8) {
        if cursorResetPending {
            pending.removeAll(keepingCapacity: true)
            cursorResetPending = false
        }
        guard pending.count < maximumPendingBytes else { return }
        pending.append(byte)
    }

    private mutating func emit(into finished: inout [AssembledLine]) {
        // Decodes once, because this runs for every line a command prints.
        let text = String(decoding: pending, as: UTF8.self)
        pending.removeAll(keepingCapacity: true)
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            // Keep leading indentation, which distinguishes rows from section titles.
            finished.append(AssembledLine(text: text.droppingTrailingWhitespace, fromAlternateScreen: inAlternateScreen))
        }
    }

    private mutating func finishCSI(final: UInt8) {
        switch final {
        case UInt8(ascii: "K"), UInt8(ascii: "J"):
            let params = tokenizer.parameters
            let isOneOrTwo = params.count == 1 && (params[0] == UInt8(ascii: "1") || params[0] == UInt8(ascii: "2"))
            // Erasing from the start or whole line discards what was pending.
            if isOneOrTwo || cursorResetPending {
                pending.removeAll(keepingCapacity: true)
                cursorResetPending = false
            }
        case UInt8(ascii: "h"), UInt8(ascii: "l"):
            let params = tokenizer.parameters
            guard params.first == UInt8(ascii: "?") else { break }
            let body = String(decoding: params.dropFirst(), as: UTF8.self)
            let modes = body.split(separator: ";")
            if modes.contains(where: { $0 == "1049" || $0 == "47" || $0 == "1047" }) {
                inAlternateScreen = final == UInt8(ascii: "h")
            }
        default:
            break
        }
    }
}
