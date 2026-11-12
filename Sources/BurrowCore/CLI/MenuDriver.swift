import Foundation

/// Operates a Mole selection menu on the user's behalf and checks every step.
///
/// The CLI has no argument for choosing rows in `mo installer`, `mo purge` or `mo slim`,
/// so the real menu runs on a virtual terminal. Those menus show at most 50 rows per page,
/// so the list can be longer than the screen and hold selected rows that aren't visible.
/// The driver therefore walks every row, compares the row under the cursor with the one
/// the user picked before pressing Space, and requires the CLI's own selected count to
/// match before it presses Enter. Any mismatch stops before Enter, which leaves nothing
/// confirmed.
@MainActor
public final class MenuDriver {
    private let terminal: CLITerminal
    private let settleTimeout: TimeInterval = 4
    private var knownItems: [MenuItem] = []
    /// The cursor's position in the whole list, which the screen alone can't show.
    private var cursorIndex = 0
    private var cachedRevision = -1
    private var cachedSnapshot: MenuSnapshot?

    public init(terminal: CLITerminal) {
        self.terminal = terminal
    }

    public var snapshot: MenuSnapshot? {
        if cachedRevision != terminal.screen.revision {
            cachedSnapshot = MenuParser.parse(lines: terminal.screen.lines)
            cachedRevision = terminal.screen.revision
        }
        return cachedSnapshot
    }

    /// Waits for the selection menu. Returns nil when the command finishes without
    /// showing one, which is how it reports having nothing to select.
    public func waitForMenu(timeout: TimeInterval = 300) async throws -> MenuSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if let menu = snapshot, menu.cursor != nil {
                // Give the rest of the first paint a moment to land.
                try await settle()
                if let settled = snapshot, settled.cursor != nil { return settled }
            }
            if !terminal.isRunning { return nil }
            try await Task.sleep(for: .milliseconds(60))
        }
        throw MenuDriverError.menuDidNotAppear
    }

    /// Reads the whole list by walking the cursor from top to bottom, then returns to
    /// the top. `progress` receives the number of rows read and the total.
    public func readItems(progress: ((Int, Int) -> Void)? = nil) async throws -> [MenuItem] {
        guard let first = snapshot, first.cursor != nil else { throw MenuDriverError.menuClosed }
        // The cursor starts on the first row.
        cursorIndex = 0
        let total = first.reportedTotal ?? first.rows.count
        let isPaged = total > first.rows.count
        if isPaged, first.position == nil {
            throw MenuDriverError.verificationFailed("the list is longer than one page and doesn't report its position")
        }
        guard total >= first.rows.count else {
            throw MenuDriverError.verificationFailed("the list reports fewer rows than it shows")
        }
        let readsPaths = first.focusedPath != nil

        var items: [MenuItem] = []
        items.reserveCapacity(total)
        if !isPaged, !readsPaths {
            items = first.rows.enumerated().map { MenuItem.parse(row: $0.element, index: $0.offset) }
        } else {
            for index in 0..<total {
                try Task.checkCancellation()
                try await moveCursor(to: index, expecting: nil)
                try await settle()
                guard let cursor = snapshot?.cursor else { throw MenuDriverError.menuClosed }
                var item = MenuItem.parse(row: cursor, index: index)
                if readsPaths { item.path = try await readFocusedPath(for: item) }
                items.append(item)
                progress?(index + 1, total)
            }
            try await moveCursor(to: 0, expecting: nil)
        }

        // The rows must add up to what the CLI says, or the list isn't fully understood.
        if let reported = first.reportedSelectedCount, reported != items.filter(\.preselected).count {
            throw MenuDriverError.verificationFailed(
                "the list reports \(reported) selected rows, but \(items.filter(\.preselected).count) were found"
            )
        }
        knownItems = items
        return items
    }

    /// Reads the `Path:` line for the focused row. The CLI paints the cursor before this
    /// line, so a read straight after moving can return the previous row's path. A path
    /// only counts once it agrees with the row, and an unconfirmed path is left out
    /// rather than shown beside the wrong item.
    private func readFocusedPath(for item: MenuItem) async throws -> String? {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            try Task.checkCancellation()
            if let path = snapshot?.focusedPath, Self.path(path, matches: item) { return path }
            try await Task.sleep(for: .milliseconds(15))
        }
        return nil
    }

    /// Rows read `project  size | artifact`, where the artifact is relative to the
    /// project and can be shortened with `...`.
    nonisolated static func path(_ path: String, matches item: MenuItem) -> Bool {
        guard path == item.name || path.hasPrefix(item.name + "/") else { return false }
        guard let tag = item.tag else { return true }
        if tag.hasSuffix("...") {
            let start = item.name + "/" + tag.dropLast(3)
            return path.hasPrefix(start)
        }
        return path == item.name + "/" + tag || path.hasSuffix("/" + tag)
    }

    /// Sets the selection to exactly `wanted`, including rows on other pages, then
    /// verifies the result against the CLI's own count. Call `readItems` first.
    public func select(_ wanted: [MenuItem]) async throws {
        guard !knownItems.isEmpty else {
            throw MenuDriverError.verificationFailed("the list hasn't been read")
        }
        let wantedByIndex = Dictionary(uniqueKeysWithValues: wanted.map { ($0.index, $0) })
        for index in wantedByIndex.keys where !knownItems.indices.contains(index) {
            throw MenuDriverError.verificationFailed("row \(index + 1) isn't in the list")
        }

        for known in knownItems {
            try Task.checkCancellation()
            let wantedItem = wantedByIndex[known.index]
            let shouldSelect = wantedItem != nil
            guard known.preselected || shouldSelect else { continue }
            let expected = wantedItem?.rowText ?? known.rowText
            try await moveCursor(to: known.index, expecting: expected)
            guard known.preselected != shouldSelect else { continue }

            let before = snapshot?.reportedSelectedCount
            terminal.send(" ")
            try await waitUntil { [self] in
                guard let menu = snapshot, let cursor = menu.cursor, cursor.isSelected == shouldSelect else {
                    return false
                }
                guard let before else { return true }
                return menu.reportedSelectedCount == before + (shouldSelect ? 1 : -1)
            }
        }

        try await settle()
        guard let final = snapshot else { throw MenuDriverError.menuClosed }
        guard let reported = final.reportedSelectedCount else {
            throw MenuDriverError.verificationFailed("the list doesn't report how many rows are selected")
        }
        guard reported == wanted.count else {
            throw MenuDriverError.verificationFailed("the list reports \(reported) rows selected, expected \(wanted.count)")
        }
        guard (final.reportedTotal ?? final.rows.count) == knownItems.count else {
            throw MenuDriverError.verificationFailed("the list changed length")
        }
    }

    /// Presses Enter on the verified selection.
    public func confirm() {
        terminal.send("\r")
    }

    /// Leaves the menu without choosing anything.
    public func quit() {
        terminal.send("q")
    }

    private func moveCursor(to target: Int, expecting expected: String?) async throws {
        while cursorIndex != target {
            try Task.checkCancellation()
            let goingDown = target > cursorIndex
            let previous = snapshot
            let next = cursorIndex + (goingDown ? 1 : -1)
            terminal.send(goingDown ? "\u{1B}[B" : "\u{1B}[A")
            try await waitUntil { [self] in
                guard let menu = snapshot else { return false }
                if let position = menu.position { return position.current == next + 1 }
                // On a single page the cursor's row is the position.
                return menu.rows.firstIndex(where: \.isCursor) == next
                    && previous?.rows.firstIndex(where: \.isCursor) != next
            }
            cursorIndex = next
        }

        guard let expected else { return }
        // Scrolling repaints the rows after the header, so allow the paint to finish.
        do {
            try await waitUntil { [self] in snapshot?.cursor?.text == expected }
        } catch MenuDriverError.verificationFailed {
            throw MenuDriverError.rowMismatch(expected: expected, found: snapshot?.cursor?.text ?? "nothing")
        }
    }

    /// Waits until the screen has stopped changing, so that a read sees a whole paint.
    private func settle() async throws {
        let deadline = Date().addingTimeInterval(settleTimeout)
        var revision = terminal.screen.revision
        var stableSince = Date()
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(10))
            if terminal.screen.revision != revision {
                revision = terminal.screen.revision
                stableSince = Date()
            } else if Date().timeIntervalSince(stableSince) >= 0.04 {
                return
            }
            if !terminal.isRunning { throw MenuDriverError.menuClosed }
        }
        throw MenuDriverError.verificationFailed("the list did not finish repainting in time")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(settleTimeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if condition() { return }
            if !terminal.isRunning { throw MenuDriverError.menuClosed }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw MenuDriverError.verificationFailed("the list did not respond in time")
    }
}
