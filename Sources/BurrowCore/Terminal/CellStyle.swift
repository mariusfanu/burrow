public struct CellStyle: Sendable, Equatable, Hashable {
    public var foreground = TerminalColor.standard
    public var background = TerminalColor.standard
    public var bold = false
    public var dim = false
    public var underline = false
    public var inverse = false

    public init() {}
}
