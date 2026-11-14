import Foundation

extension Int64 {
    @MainActor var fileSize: String { ByteFormat.file.string(fromByteCount: self) }
    @MainActor var memorySize: String { ByteFormat.memory.string(fromByteCount: self) }
    /// A transfer rate such as "3 KB/s". Rates never drop to bytes, so an idle disk reads
    /// "0 KB/s" beside "12.7 MB/s" instead of "0 bytes/s".
    @MainActor var rate: String { String(localized: "\(ByteFormat.rate.string(fromByteCount: self))/s") }
    /// A size that counts up or grows live. It never shows bytes, so the unit doesn't jump
    /// from "bytes" to "KB" on the first tick.
    @MainActor var countedSize: String { ByteFormat.rate.string(fromByteCount: self) }
}

extension Int {
    /// "1 item", "1,974 items".
    var itemCount: AttributedString { AttributedString(localized: "^[\(self) item](inflect: true)") }
}

/// Shared byte formatters. Zero is a number like any other here: "Zero KB" next to "1.2 GB"
/// reads as a different kind of value and breaks a column's rhythm.
@MainActor
enum ByteFormat {
    static let file = make(.file)
    static let memory = make(.memory)
    static let rate: ByteCountFormatter = {
        let formatter = make(.file)
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter
    }()

    private static func make(_ style: ByteCountFormatter.CountStyle) -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = style
        formatter.allowsNonnumericFormatting = false
        return formatter
    }
}
