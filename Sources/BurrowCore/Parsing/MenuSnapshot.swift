/// A parsed view of a selection menu on the screen.
public struct MenuSnapshot: Sendable {
    public let title: String
    public let rows: [MenuRow]
    /// One-based position and total from the `[pos/total]` scroll indicator, which
    /// the CLI prints only when the list is longer than a page.
    public let position: (current: Int, total: Int)?
    /// How many rows the CLI says are selected, including rows on other pages.
    public let reportedSelectedCount: Int?
    /// The list length, from the scroll indicator or a `3/9 selected` count.
    public let reportedTotal: Int?
    /// Lines between the last row and the key hints, which name the focused item.
    public let details: [String]

    public var cursor: MenuRow? { rows.first(where: \.isCursor) }
    /// Full path of the focused row where the menu prints one (`Path: ...`).
    public var focusedPath: String? {
        details.first { $0.hasPrefix("Path:") }.map {
            String($0.dropFirst("Path:".count)).trimmingCharacters(in: .whitespaces)
        }
    }
}
