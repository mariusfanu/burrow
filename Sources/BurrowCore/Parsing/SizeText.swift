import Foundation

public extension Sequence<Int64> {
    /// Adds sizes parsed from CLI text, stopping at the largest value instead of trapping.
    var saturatingSum: Int64 {
        reduce(0) { total, next in
            let (sum, overflow) = total.addingReportingOverflow(next)
            return overflow ? (next > 0 ? Int64.max : Int64.min) : sum
        }
    }
}

public enum SizeText {
    // A regex literal inside a function is compiled again on every call. This runs per line.
    nonisolated(unsafe) private static let size = /\b(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)\b/

    /// Parses a size such as `93.6MB`, `7.07GB+` or `786KB`, using the CLI's decimal units.
    public static func bytes(from text: String) -> Int64? {
        guard let match = text.firstMatch(of: size) else { return nil }
        guard let value = Double(match.1) else { return nil }
        let multiplier: Double
        switch match.2 {
        case "KB": multiplier = 1_000
        case "MB": multiplier = 1_000_000
        case "GB": multiplier = 1_000_000_000
        case "TB": multiplier = 1_000_000_000_000
        default: multiplier = 1
        }
        // The text can come from a file name, so a huge number mustn't trap.
        let bytes = value * multiplier
        return bytes < Double(Int64.max) ? Int64(bytes) : Int64.max
    }
}
