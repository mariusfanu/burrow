import Foundation

/// Parses completed terminal lines once, retaining only the report and unfinished line.
/// Snapshots are values: later chunks never mutate a previously published report.
public struct CleanReportParser: Sendable {
    private var assembler = LineAssembler()
    private var report = CleanReport()
    private var nextRowID = 0
    private var isFinished = false
    public private(set) var announcedPathList: String?

    public init() {}

    public var snapshot: CleanReport { report }

    public mutating func feed(_ data: Data) {
        guard !isFinished else { return }
        for line in assembler.feed(data) { consume(line.text) }
    }

    public mutating func finish(pathList: String? = nil) -> CleanReport {
        if !isFinished {
            let tail = assembler.partialLine
            if !tail.isEmpty { consume(tail) }
            isFinished = true
        }
        if let pathList {
            let entries = CleanReport.parsePathList(pathList)
            for index in report.sections.indices {
                report.sections[index].paths = entries[report.sections[index].name] ?? []
            }
        }
        return report
    }

    // Kept here because a regex literal inside a function is compiled on every call.
    nonisolated(unsafe) private static let potentialSpace = /^Potential space:\s*(\S+)(?:\s*·\s*(\d+)\s+items?)?/

    private mutating func consume(_ raw: String) {
        guard !LogLine.isDecoration(raw) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let detailPrefix = "Detailed file list: "
        if trimmed.hasPrefix(detailPrefix) {
            announcedPathList = String(trimmed.dropFirst(detailPrefix.count))
            return
        }
        if let summary = trimmed.firstMatch(of: Self.potentialSpace) {
            report.potentialText = String(summary.1)
            report.itemCount = summary.2.flatMap { Int($0) }
            return
        }
        let line = LogLine(id: nextRowID, raw: raw)
        nextRowID += 1
        if line.kind == .section {
            report.sections.append(.init(name: line.title))
            return
        }
        guard let index = report.sections.indices.last else {
            if line.kind == .note || line.kind == .meta { report.notes.append(line.text) }
            return
        }
        // Text after the last section is closing chatter, not a cleanup row.
        if line.kind == .plain, !line.isIndented { return }
        report.sections[index].append(line)
    }
}
