import Darwin
import Foundation

/// Writes the same `operations.log` and `deletions.log` rows `cmd/analyze/oplog.go` writes,
/// so `mo history` and support diagnostics see Trash moves made from this app.
public final class OperationsLog: @unchecked Sendable {
    private let operationsPath: String
    private let deletionsPath: String
    /// `MO_NO_OPLOG` silences operations.log only. deletions.log is always written,
    /// matching `cmd/analyze/oplog.go`.
    private let operationsEnabled: Bool
    private let commandField: String
    private let lock = NSLock()
    private var failed = false

    /// True once any append has failed.
    public var writeFailed: Bool {
        lock.withLock { failed }
    }

    public init(home: String, command: String, environment: [String: String]) {
        let logDirectory = home + "/Library/Logs/mole"
        operationsPath = logDirectory + "/operations.log"
        deletionsPath = environment["MOLE_DELETE_LOG"] ?? (logDirectory + "/deletions.log")
        operationsEnabled = environment["MO_NO_OPLOG"] != "1"

        let stamp = Self.timestamp(format: "yyyyMMddHHmmss")
        let runID = "\(stamp)-\(getpid())-\(Int.random(in: 0...32_767))-\(Int.random(in: 0...32_767))"
        commandField = "\(command) run=\(runID)"
    }

    public func begin() {
        appendOperation(["", "# ========== \(commandField) session started at \(Self.timestamp()) =========="])
    }

    public func recordTrashed(path: String, size: Int64) {
        var line = "[\(Self.timestamp())] [\(commandField)] TRASHED \(Self.escape(path))"
        if size > 0 { line += " (\(Self.sizeText(size)))" }
        appendOperation([line])
        appendDeletion(path: path, size: size, status: "ok")
    }

    public func recordRestored(path: String) {
        appendOperation(["[\(Self.timestamp())] [\(commandField)] RESTORED \(Self.escape(path))"])
    }

    public func recordFailed(path: String, size: Int64, reason: String) {
        appendOperation(["[\(Self.timestamp())] [\(commandField)] FAILED \(Self.escape(path)) (\(reason))"])
        appendDeletion(path: path, size: size, status: "trash-failed")
    }

    private func appendDeletion(path: String, size: Int64, status: String) {
        let bytes = max(size, 0)
        let sizeKB = bytes / 1024 + (bytes % 1024 == 0 ? 0 : 1)
        let stamp = Self.timestamp(format: "yyyy-MM-dd'T'HH:mm:ssZ")
        let fields = [stamp, "trash", String(sizeKB), status, Self.escape(path)]
        append([fields.joined(separator: "\t")], to: deletionsPath)
    }

    public func end(items: Int, bytes: Int64) {
        appendOperation(
            ["# ========== \(commandField) session ended at \(Self.timestamp()), \(items) items, \(Self.sizeText(bytes)) =========="]
        )
    }

    /// Writes control bytes as `\n`, `\r`, `\t` or `\xHH` so a filename can't forge a record.
    /// Backslashes stay literal, matching `_mole_escape_log_value`.
    public static func escape(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.utf8.count)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x0A: output += "\\n"
            case 0x0D: output += "\\r"
            case 0x09: output += "\\t"
            case 0..<0x20, 0x7F: output += String(format: "\\x%02x", scalar.value)
            default: output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    /// Mirrors `bytes_to_human` in `lib/core/base.sh`.
    public static func sizeText(_ bytes: Int64) -> String {
        switch bytes {
        case 1_000_000_000...:
            // Round hundredths after division so even a saturated byte total stays in range.
            let scaled = bytes / 10_000_000 + (bytes % 10_000_000 >= 5_000_000 ? 1 : 0)
            return "\(scaled / 100).\(String(format: "%02d", scaled % 100))GB"
        case 1_000_000...:
            let scaled = (bytes * 10 + 500_000) / 1_000_000
            return "\(scaled / 10).\(scaled % 10)MB"
        case 1_000...:
            return "\((bytes + 500) / 1_000)KB"
        default:
            return "\(max(bytes, 0))B"
        }
    }

    private static func timestamp(format: String = "yyyy-MM-dd HH:mm:ss") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: Date())
    }

    private func appendOperation(_ lines: [String]) {
        guard operationsEnabled else { return }
        append(lines, to: operationsPath)
    }

    /// Appends with `O_APPEND`, so a row can't overwrite one another process just wrote.
    private func append(_ lines: [String], to path: String) {
        let text = lines.joined(separator: "\n") + "\n"
        do {
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            guard descriptor >= 0 else { throw POSIXError(.EIO) }
            defer { close(descriptor) }
            let bytes = Array(text.utf8)
            let written = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            guard written == bytes.count else { throw POSIXError(.EIO) }
        } catch {
            lock.withLock { failed = true }
        }
    }
}
