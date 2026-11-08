import Foundation

/// One row of a Mole shell selection menu, as read from the terminal screen.
public struct MenuRow: Sendable, Equatable {
    public let isCursor: Bool
    public let isSelected: Bool
    /// The row text after the cursor and checkbox.
    public let text: String
}

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

public enum MenuParser {
    /// The line of key hints under every menu.
    public static func isKeyHint(_ line: String) -> Bool {
        line.contains("Space Select")
    }

    /// Reads a menu from screen lines, or returns nil if none is showing.
    /// The key-hint line is what identifies a menu, so ordinary output that
    /// happens to contain a bullet can never be treated as selectable rows.
    public static func parse(lines: [String]) -> MenuSnapshot? {
        guard let hintIndex = lines.lastIndex(where: isKeyHint) else { return nil }

        var rows: [MenuRow] = []
        var header: [String] = []
        var lastRowIndex: Int?
        for index in 0..<hintIndex {
            let line = lines[index]
            if let row = parseRow(line) {
                rows.append(row)
                lastRowIndex = index
            } else if rows.isEmpty, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                header.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        guard let lastRowIndex else { return nil }

        // Counts come only from the header, so a file name in a row can't supply them.
        let headerText = header.joined(separator: "\n")
        var position: (current: Int, total: Int)?
        if let match = headerText.firstMatch(of: positionPattern),
           let current = Int(match.1), let total = Int(match.2) {
            position = (current, total)
        }
        var selectedCount: Int?
        var countTotal: Int?
        if let match = headerText.firstMatch(of: selectedCountPattern) {
            selectedCount = Int(match.1)
            countTotal = match.2.flatMap { Int($0) }
        }

        let details = lines[(lastRowIndex + 1)..<hintIndex]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return MenuSnapshot(
            title: header.first ?? "",
            rows: rows,
            position: position,
            reportedSelectedCount: selectedCount,
            reportedTotal: position?.total ?? countTotal,
            details: details
        )
    }

    // A regex literal inside a function is compiled again on every call. This runs per line.
    nonisolated(unsafe) private static let row = /^\s*(➤)?\s*([○●])\s+(.*)$/
    nonisolated(unsafe) private static let positionPattern = /\[(\d+)\/(\d+)\]/
    nonisolated(unsafe) private static let selectedCountPattern = /(\d+)(?:\/(\d+))? selected/

    public static func parseRow(_ line: String) -> MenuRow? {
        guard let match = line.firstMatch(of: row) else { return nil }
        return MenuRow(
            isCursor: match.1 != nil,
            isSelected: match.2 == "●",
            text: String(match.3).trimmingCharacters(in: .whitespaces)
        )
    }
}

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
