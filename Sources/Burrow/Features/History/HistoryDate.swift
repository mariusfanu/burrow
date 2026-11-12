import Foundation

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
