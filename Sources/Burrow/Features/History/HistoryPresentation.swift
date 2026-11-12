import BurrowCore
import Foundation

/// How a history session reads in the interface. The CLI's log speaks in command names,
/// timestamps and packed sizes such as `82.84GB`. People read page names, "Yesterday at
/// 23:39" and "82.84 GB".
extension HistoryReport.Session {
    /// The page name where there is one, so History and the sidebar agree.
    var title: String {
        switch commandName {
        case "clean": "Clean"
        case "uninstall": "Uninstall"
        case "purge": "Project Purge"
        case "installer", "installers": "Installers"
        case "slim": "Slim Apps"
        case "optimize": "Optimize"
        case "analyze": "Disk Explorer"
        case "touchid": "Touch ID"
        case "update": "Update"
        case "completion": "Shell Completion"
        case "remove": "Remove Mole"
        default: commandName.capitalized
        }
    }

    /// The page's symbol, or a terminal for commands that only run in Settings.
    var symbol: String {
        if commandName == "touchid" { return "touchid" }
        if commandName == "update" { return "arrow.down.circle" }
        return Screen.allCases.first { $0.rawValue.hasPrefix(commandName) }?.symbol ?? "terminal"
    }

    var startedDate: Date? { startedAt.flatMap(HistoryDate.parse) }

    /// "Yesterday at 23:39", falling back to the raw text if it can't be read as a date.
    var startedText: String {
        guard let date = startedDate else { return startedAt ?? "" }
        return HistoryDate.text(for: date)
    }

    var bytes: Int64 { SizeText.bytes(from: size ?? "") ?? 0 }

    /// The size column, or nothing when the session didn't free anything. A column of
    /// "0 bytes" says nothing and hides the rows that matter.
    var sizeText: String? { bytes > 0 ? bytes.fileSize : nil }

    /// "1 item", "1,974 items", or nothing when no item was involved.
    var itemsText: AttributedString? {
        guard let items, items > 0 else { return nil }
        return AttributedString(localized: "^[\(items) item](inflect: true)")
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
    var timestampText: String {
        guard let timestamp, let date = HistoryDate.parse(timestamp) else { return timestamp ?? "" }
        return HistoryDate.text(for: date)
    }
}

/// Reads the CLI's timestamps and writes them the way the Finder does.
enum HistoryDate {
    // Formatters are safe to share once configured, and these are never changed again.
    private static let parsers: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ssXXXXX",
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Autoupdating, so a time-zone change while the app runs is honored as it was before.
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }

    private static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static func parse(_ text: String) -> Date? {
        for parser in parsers {
            if let date = parser.date(from: text) { return date }
        }
        return nil
    }

    static func text(for date: Date) -> String {
        display.string(from: date)
    }
}
