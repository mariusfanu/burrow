import Foundation

/// Splits a terminal stream into text and finished escape sequences, one byte at a time.
///
/// `TerminalScreen` and `LineAssembler` do different jobs with the same stream, so they share
/// this instead of each carrying the grammar, which is how their readings came to differ.
struct EscapeTokenizer: Sendable {
    enum Token: Sendable {
        /// A byte outside any sequence, including control characters.
        case text(UInt8)
        /// `ESC` and one byte, such as `ESC 7`.
        case escape(UInt8)
        /// A control sequence, with its bytes in `parameters`.
        case csi(final: UInt8)
        /// An operating system command, with its start in `oscText`.
        case osc
        /// A sequence with nothing to act on, such as a character set choice.
        case ignored
    }

    private enum State {
        case text
        case escape
        case csi
        case osc
        case oscEscape
        case charset
    }

    private var state = State.text
    /// The bytes between `ESC [` and the final byte of the sequence just reported.
    private(set) var parameters: [UInt8] = []
    /// The start of the command just reported, long enough to recognize a color query. Nil
    /// for strings such as `ESC P`, which end the same way but aren't commands.
    private(set) var oscText: [UInt8]?

    /// Takes the next byte, and returns a token if it finished one.
    @inline(__always)
    mutating func next(_ byte: UInt8) -> Token? {
        switch state {
        case .text:
            if byte == 0x1B {
                state = .escape
                return nil
            }
            return .text(byte)
        case .escape:
            state = .text
            switch byte {
            case UInt8(ascii: "["):
                parameters.removeAll(keepingCapacity: true)
                state = .csi
            case UInt8(ascii: "]"):
                oscText = []
                state = .osc
            case UInt8(ascii: "P"), UInt8(ascii: "_"), UInt8(ascii: "^"):
                oscText = nil
                state = .osc
            case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: "#"):
                state = .charset
            default:
                return .escape(byte)
            }
            return nil
        case .csi:
            if byte >= 0x40, byte <= 0x7E {
                state = .text
                return .csi(final: byte)
            }
            if byte == 0x1B {
                state = .escape
            } else {
                parameters.append(byte)
            }
            return nil
        case .osc:
            if byte == 0x07 {
                state = .text
                return .osc
            }
            if byte == 0x1B {
                state = .oscEscape
            } else if let text = oscText, text.count < 16 {
                oscText?.append(byte)
            }
            return nil
        case .oscEscape:
            if byte == UInt8(ascii: "\\") {
                state = .text
                return .osc
            }
            state = .osc
            return nil
        case .charset:
            state = .text
            return .ignored
        }
    }
}
