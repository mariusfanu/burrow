import Foundation

/// The result of `mo history --json`.
public struct HistoryReport: Decodable, Sendable, Equatable {
    public struct Logs: Decodable, Sendable, Equatable {
        public var operations: String?
        public var deletions: String?
    }

    public struct Actions: Decodable, Sendable, Equatable {
        public var removed: Int?
        public var trashed: Int?
        public var skipped: Int?
        public var failed: Int?
        public var rebuilt: Int?
    }

    public struct Session: Decodable, Sendable, Equatable, Identifiable {
        public var command: String?
        public var runId: String?
        public var startedAt: String?
        public var items: Int?
        public var size: String?
        public var operationCount: Int?
        public var failedTasks: Int?
        public var actions: Actions?

        public var id: String {
            "\(runId ?? "")|\(command ?? "")|\(startedAt ?? "")"
        }

        public var isPreview: Bool {
            command?.hasSuffix("-dry-run") ?? false
        }

        public var commandName: String {
            guard let command else { return "unknown" }
            return command.replacingOccurrences(of: "-dry-run", with: "")
        }
    }

    public struct Deletion: Decodable, Sendable, Equatable, Identifiable {
        public var timestamp: String?
        public var mode: String?
        public var status: String?
        public var sizeKb: Int64?
        public var path: String?
        public var id: String { "\(timestamp ?? "")|\(path ?? "")" }

        /// Deletion logs round bytes up to KiB, which can put a saturated size just over
        /// Int64.max when converted back. Keep that size representable for display.
        public var bytes: Int64? {
            guard let sizeKb else { return nil }
            let (bytes, overflow) = sizeKb.multipliedReportingOverflow(by: 1_024)
            return overflow ? (sizeKb > 0 ? .max : .min) : bytes
        }
    }

    public var logs: Logs?
    public var limit: Int?
    public var sessions: [Session]?
    public var deletions: [Deletion]?

    public static func decode(_ data: Data) throws -> HistoryReport {
        try JSONDecoder.forCLI().decode(HistoryReport.self, from: data)
    }
}
