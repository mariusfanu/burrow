import Darwin
import Foundation

/// Moves Analyze selections to the Trash and records them where the CLI records its own.
public enum TrashMover {
    /// Identifies a file for as long as it exists, wherever it moves on its volume.
    public struct FileIdentity: Sendable, Equatable {
        let device: Int64
        let inode: UInt64

        public init?(path: String) {
            var info = stat()
            guard lstat(path, &info) == 0 else { return nil }
            device = Int64(info.st_dev)
            inode = UInt64(info.st_ino)
        }
    }

    /// A move that can be undone.
    public struct TrashedItem: Sendable {
        public let trashedURL: URL
        public let originalPath: String
        /// What was moved. Another item can take the same name once the Trash is emptied.
        public let identity: FileIdentity?

        public init(trashedURL: URL, originalPath: String, identity: FileIdentity? = nil) {
            self.trashedURL = trashedURL
            self.originalPath = originalPath
            self.identity = identity
        }
    }

    public struct NotTheSameItem: LocalizedError {
        public let path: String
        public var errorDescription: String? {
            "\((path as NSString).lastPathComponent) wasn’t put back, because the item now in the Trash isn’t the one Burrow moved."
        }
    }

    public struct Outcome: Sendable {
        public let path: String
        public let error: String?
        /// Where the item landed in the Trash, which is what makes Undo possible.
        public let trashedURL: URL?
        public let trashedIdentity: FileIdentity?

        public init(path: String, error: String?, trashedURL: URL? = nil, trashedIdentity: FileIdentity? = nil) {
            self.path = path
            self.error = error
            self.trashedURL = trashedURL
            self.trashedIdentity = trashedIdentity
        }

        /// What Undo needs, when the item's new location is known.
        public var trashedItem: TrashedItem? {
            trashedURL.map { TrashedItem(trashedURL: $0, originalPath: path, identity: trashedIdentity) }
        }
    }

    public struct Report: Sendable {
        public let outcomes: [Outcome]
        /// True when the audit trail couldn't be written, which the user must be told.
        public let logFailed: Bool

        public init(outcomes: [Outcome], logFailed: Bool) {
            self.outcomes = outcomes
            self.logFailed = logFailed
        }
    }

    private static let trashBinary = "/usr/bin/trash"

    /// Uses the system Trash API, which reports where the item went so that it can be put
    /// back. trash(8), the tool the CLI uses, covers any case where that fails, but then
    /// the item's new location is unknown. Neither overwrites an existing Trash item.
    private static func moveToTrash(_ path: String, environment: [String: String]) async throws -> URL? {
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
            return resulting as URL?
        } catch {
            guard FileManager.default.isExecutableFile(atPath: trashBinary) else { throw error }
            let result = try await CommandRunner.run(
                executable: trashBinary,
                arguments: [path],
                environment: environment,
                timeout: 30
            )
            guard result.succeeded else {
                throw CommandError.failed(status: result.status, message: result.stderr)
            }
            return nil
        }
    }

    /// Puts trashed items back where they were. It never overwrites: if something now
    /// exists at the original path, that item stays in the Trash and reports an error. The
    /// same goes for a different item that has since taken the trashed item's name.
    public static func restore(
        _ items: [TrashedItem],
        home: String = NSHomeDirectory(),
        environment: [String: String] = CLILocator.environment()
    ) -> Report {
        let audit = OperationsLog(home: home, command: "analyze", environment: environment)
        audit.begin()
        var outcomes: [Outcome] = []
        for item in items {
            do {
                guard let identity = item.identity, FileIdentity(path: item.trashedURL.path) == identity else {
                    throw NotTheSameItem(path: item.originalPath)
                }
                try FileManager.default.moveItem(at: item.trashedURL, to: URL(fileURLWithPath: item.originalPath))
                audit.recordRestored(path: item.originalPath)
                outcomes.append(Outcome(path: item.originalPath, error: nil))
            } catch {
                audit.recordFailed(path: item.originalPath, size: 0, reason: "restore-failed")
                outcomes.append(Outcome(path: item.originalPath, error: error.localizedDescription))
            }
        }
        audit.end(items: outcomes.filter { $0.error == nil }.count, bytes: 0)
        return Report(outcomes: outcomes, logFailed: audit.writeFailed)
    }

    /// Validates and trashes each path in order. A refused path doesn't stop the others.
    public static func trash(
        entries: [(path: String, size: Int64)],
        guardrail: TrashGuard = TrashGuard(),
        home: String = NSHomeDirectory(),
        environment: [String: String] = CLILocator.environment()
    ) async -> Report {
        var outcomes: [Outcome] = []
        let audit = OperationsLog(home: home, command: "analyze", environment: environment)
        audit.begin()
        var trashedCount = 0
        var trashedBytes: Int64 = 0

        for entry in entries {
            do {
                try guardrail.validate(entry.path)
                // A path that's already gone is not logged, because nothing was done to it.
                var info = stat()
                if lstat(entry.path, &info) != 0, errno == ENOENT {
                    outcomes.append(Outcome(path: entry.path, error: nil))
                    continue
                }
                let trashedURL = try await moveToTrash(entry.path, environment: environment)
                // Offer Undo only when the item can be verified before restoring it.
                let identity = trashedURL.flatMap { FileIdentity(path: $0.path) }
                audit.recordTrashed(path: entry.path, size: entry.size)
                trashedCount += 1
                trashedBytes = [trashedBytes, entry.size].saturatingSum
                outcomes.append(Outcome(
                    path: entry.path,
                    error: nil,
                    trashedURL: identity == nil ? nil : trashedURL,
                    trashedIdentity: identity
                ))
            } catch let refusal as TrashGuard.Refusal {
                audit.recordFailed(path: entry.path, size: entry.size, reason: "protected")
                outcomes.append(Outcome(path: entry.path, error: refusal.localizedDescription))
            } catch {
                audit.recordFailed(path: entry.path, size: entry.size, reason: "trash-failed")
                outcomes.append(Outcome(path: entry.path, error: error.localizedDescription))
            }
        }
        audit.end(items: trashedCount, bytes: trashedBytes)
        return Report(outcomes: outcomes, logFailed: audit.writeFailed)
    }
}
