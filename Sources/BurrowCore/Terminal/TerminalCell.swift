public struct TerminalCell: Sendable, Equatable {
    public var character: Character = " "
    public var style = CellStyle()
    /// A wide glyph occupies this cell and a trailing continuation cell.
    public var isContinuation = false

    public init() {}
}
