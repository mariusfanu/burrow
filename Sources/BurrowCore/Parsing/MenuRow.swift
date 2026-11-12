/// One row of a Mole shell selection menu, as read from the terminal screen.
public struct MenuRow: Sendable, Equatable {
    public let isCursor: Bool
    public let isSelected: Bool
    /// The row text after the cursor and checkbox.
    public let text: String
}
