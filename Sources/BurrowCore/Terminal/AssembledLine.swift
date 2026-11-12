public struct AssembledLine: Sendable, Equatable {
    public let text: String
    /// True when the line was printed while the program held the alternate screen.
    public let fromAlternateScreen: Bool
}
