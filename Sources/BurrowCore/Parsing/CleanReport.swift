import Foundation

/// The result of a `mo clean --dry-run` preview.
public struct CleanReport: Sendable, Equatable {
    public typealias Row = LogLine

    public struct Section: Identifiable, Sendable, Equatable {
        public var id: String { name }
        public let name: String
        public private(set) var rows: [Row] = []
        public var paths: [PathEntry] = []
        /// Kept as rows arrive, because a scan's views read this several times per update.
        public private(set) var bytes: Int64 = 0

        init(name: String) { self.name = name }

        mutating func append(_ row: Row) {
            rows.append(row)
            if row.kind == .preview, let size = row.bytes { bytes = [bytes, size].saturatingSum }
        }

        public var isEmpty: Bool {
            !rows.contains { $0.kind != .success }
        }
    }

    public struct PathEntry: Identifiable, Sendable, Equatable {
        public var id: String { path }
        public let path: String
        public let sizeText: String
        public let bytes: Int64
    }

    public var sections: [Section] = []
    public var potentialText: String?
    public var itemCount: Int?
    public var notes: [String] = []

    public var potentialBytes: Int64 {
        if let potentialText, let parsed = SizeText.bytes(from: potentialText) { return parsed }
        return sections.map(\.bytes).saturatingSum
    }

    /// True when the preview says that cleaning will empty the Trash.
    public var emptiesTrash: Bool {
        sections.contains { section in
            section.rows.contains { $0.kind == .preview && $0.title == "Trash" }
        }
    }

    public init() {}

    public static func parse(preview output: String, pathList: String?) -> CleanReport {
        var parser = CleanReportParser()
        parser.feed(Data(output.utf8))
        return parser.finish(pathList: pathList)
    }

    // Kept here because a regex literal inside a function is compiled on every call.
    nonisolated(unsafe) private static let pathListHeading = /^=== (.+) ===$/

    /// Parses `clean-list.txt`: `=== Section ===` headings over `path  # size` rows.
    public static func parsePathList(_ text: String) -> [String: [PathEntry]] {
        var result: [String: [PathEntry]] = [:]
        var section: String?
        for line in text.split(whereSeparator: \.isNewline) {
            if let heading = line.firstMatch(of: pathListHeading) {
                section = String(heading.1)
                continue
            }
            guard let section, !line.hasPrefix("#") else { continue }
            guard let separator = line.range(of: "  # ", options: .backwards) else { continue }
            let path = String(line[..<separator.lowerBound])
            let size = String(line[separator.upperBound...])
            result[section, default: []].append(
                PathEntry(path: path, sizeText: size, bytes: SizeText.bytes(from: size) ?? 0)
            )
        }
        for key in result.keys {
            result[key]?.sort { $0.bytes > $1.bytes }
        }
        return result
    }
}
