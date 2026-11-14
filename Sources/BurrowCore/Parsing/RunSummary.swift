import Foundation

/// The result a finished command reported, read from its closing lines.
public struct RunSummary: Sendable, Equatable {
    public let bytes: Int64
    public let sizeText: String
    /// True for previews, which report what would be freed.
    public let isEstimate: Bool

    // A regex literal inside a function is compiled again on every call, and this checks
    // every line a command printed.
    nonisolated(unsafe) private static let intelCode = /(\d+(?:\.\d+)?(?:B|KB|MB|GB|TB)) of Intel code/
    nonisolated(unsafe) private static let reportedSpace = /(?i)(estimated space freed|freed|would free approximately|would free|potential space)[:\s]+~?(\d+(?:\.\d+)?(?:B|KB|MB|GB|TB))\b/

    /// Finds the last line that reports space, such as `Space freed: 2.02GB` or
    /// `Removed 1 app, freed 8KB`. Only closing lines are read, because this runs on the main
    /// thread when a command ends, and a command can print a very long listing.
    public static func parse(lines: some BidirectionalCollection<String>) -> RunSummary? {
        for line in lines.suffix(500).reversed() {
            // `mo slim --dry-run` closes with `9 apps, 381.7MB of Intel code`.
            if let match = line.firstMatch(of: intelCode),
               let bytes = SizeText.bytes(from: String(match.1)) {
                return RunSummary(bytes: bytes, sizeText: String(match.1), isEstimate: true)
            }
            guard let match = line.firstMatch(of: reportedSpace) else {
                continue
            }
            let size = String(match.2)
            guard let bytes = SizeText.bytes(from: size) else { continue }
            let label = match.1.lowercased()
            return RunSummary(
                bytes: bytes,
                sizeText: size,
                isEstimate: label.contains("would") || label.contains("potential") || label.contains("estimated")
            )
        }
        return nil
    }
}
