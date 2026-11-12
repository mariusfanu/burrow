/// A selectable item surfaced from a menu row.
public struct MenuItem: Identifiable, Sendable, Equatable, Hashable {
    // Kept here because a regex literal inside a function is compiled on every call.
    nonisolated(unsafe) private static let sizedName = /^(.*\S)\s+(\d+(?:\.\d+)?(?:B|KB|MB|GB|TB))$/

    /// Position in the menu's own order.
    public let index: Int
    public let rowText: String
    public let name: String
    public let sizeText: String?
    public let bytes: Int64
    public let tag: String?
    public let age: String?
    public var path: String?
    public let preselected: Bool

    public var id: Int { index }

    public static func parse(row: MenuRow, index: Int) -> MenuItem {
        // Rows are `name  size | tag | age`, with an optional tree glyph in front.
        var text = row.text
        for glyph in ["┌", "├", "└", "─"] where text.hasPrefix(glyph) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        let fields = text.components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) }
        let head = fields[0]

        var name = head
        var sizeText: String?
        if let match = head.firstMatch(of: Self.sizedName) {
            name = String(match.1)
            sizeText = String(match.2)
        }
        return MenuItem(
            index: index,
            rowText: row.text,
            name: name,
            sizeText: sizeText,
            bytes: sizeText.flatMap(SizeText.bytes(from:)) ?? 0,
            tag: fields.count > 1 ? fields[1] : nil,
            age: fields.count > 2 ? fields[2] : nil,
            preselected: row.isSelected
        )
    }
}
