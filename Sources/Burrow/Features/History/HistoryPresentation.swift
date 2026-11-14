import BurrowCore
import Foundation

/// How a history session reads in the interface. The CLI's log speaks in command names,
/// timestamps and packed sizes such as `82.84GB`. People read page names, "Yesterday at
/// 23:39" and "82.84 GB".
extension HistoryReport.Session {
    /// The page name where there is one, so History and the sidebar agree.
    var title: String {
        if let screen = Screen(commandName: commandName) { return screen.title }
        switch commandName {
        case "touchid": return "Touch ID"
        case "update": return "Update"
        case "completion": return "Shell Completion"
        case "remove": return "Remove Mole"
        default: return commandName.capitalized
        }
    }

    /// The page's symbol, or a terminal for commands without a page.
    var symbol: String {
        switch commandName {
        case "touchid": "touchid"
        case "update": "arrow.down.circle"
        default: Screen(commandName: commandName)?.symbol ?? "terminal"
        }
    }

    @MainActor var startedDate: Date? { startedAt.flatMap { HistoryDate.parse($0) } }

    /// "Yesterday at 23:39", falling back to the raw text if it can't be read as a date.
    @MainActor var startedText: String {
        guard let date = startedDate else { return startedAt ?? "" }
        return HistoryDate.text(for: date)
    }

    /// False for a logged session that touched nothing, which History leaves out.
    var recordedWork: Bool { (items ?? 0) > 0 || (operationCount ?? 0) > 0 }

    var bytes: Int64 { SizeText.bytes(from: size ?? "") ?? 0 }

    /// The size column, or nothing when the session didn't free anything. A column of
    /// "0 bytes" says nothing and hides the rows that matter.
    @MainActor var sizeText: String? { bytes > 0 ? bytes.fileSize : nil }

    /// "1 item", "1,974 items", or nothing when no item was involved.
    var itemsText: AttributedString? {
        guard let items, items > 0 else { return nil }
        return items.itemCount
    }

    /// What happened, such as "2,145 removed · 271 skipped".
    var actionSummary: String {
        guard let actions else { return "" }
        return [
            ("removed", actions.removed), ("trashed", actions.trashed), ("rebuilt", actions.rebuilt),
            ("skipped", actions.skipped), ("failed", actions.failed),
        ]
        .compactMap { name, count in
            guard let count, count > 0 else { return nil }
            return "\(count.formatted()) \(name)"
        }
        .joined(separator: " · ")
    }

    var hadFailures: Bool { (failedTasks ?? 0) > 0 || (actions?.failed ?? 0) > 0 }
}

extension HistoryReport.Deletion {
    @MainActor var timestampText: String {
        guard let timestamp, let date = HistoryDate.parse(timestamp) else { return timestamp ?? "" }
        return HistoryDate.text(for: date)
    }
}
