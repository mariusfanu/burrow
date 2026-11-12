import Foundation

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
