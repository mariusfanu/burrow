/// An RGB color, or one of the terminal's palette entries.
public enum TerminalColor: Sendable, Equatable, Hashable {
    case standard
    case palette(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}
