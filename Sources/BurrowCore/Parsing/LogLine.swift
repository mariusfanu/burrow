import Foundation

/// One line of CLI output, classified from the icon the CLI puts in front of it.
public struct LogLine: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case section
        case success
        case preview
        case note
        case review
        case meta
        case failure
        case plain
    }

    public let id: Int
    /// The line as the CLI printed it.
    public let raw: String
    public let kind: Kind
    public let title: String
    public let detail: String?
    public let bytes: Int64?
    public let isIndented: Bool

    /// Text as the CLI printed it, without the leading icon.
    public var text: String {
        if let detail { return "\(title) · \(detail)" }
        return title
    }

    public init(id: Int, raw: String) {
        self.id = id
        self.raw = raw
        isIndented = raw.hasPrefix(" ")
        var body = raw.trimmingCharacters(in: .whitespaces)
        kind = Self.classify(&body)

        if let range = body.range(of: " · ") {
            title = String(body[..<range.lowerBound])
            var rest = String(body[range.upperBound...])
            if rest.hasSuffix(" dry") { rest.removeLast(4) }
            detail = rest
            bytes = SizeText.bytes(from: rest)
        } else if let match = body.firstMatch(of: Self.alignedSize) {
            // Aligned `name   size` listings, as printed by `mo slim --dry-run`.
            title = String(match.1)
            detail = String(match.2)
            bytes = SizeText.bytes(from: String(match.2))
        } else {
            title = body
            detail = nil
            bytes = nil
        }
    }

    // Kept here because this runs for every line, and a literal inside a function is
    // compiled again on every call.
    nonisolated(unsafe) private static let alignedSize = /^(.*\S)\s{2,}(\d+(?:\.\d+)?(?:B|KB|MB|GB|TB))$/
    private static func classify(_ body: inout String) -> Kind {
        let kind: Kind
        switch body.first {
        case "➤": kind = .section
        case "✓": kind = .success
        case "○": kind = .preview
        case "◎": kind = .note
        case "⊙": kind = .review
        case "⚙": kind = .meta
        case "☻", "✗", "✘": kind = .failure
        case "•", "↳": kind = .plain
        default: return .plain
        }
        body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
        return kind
    }

    /// Lines that repeat what Burrow's window already says: the CLI's banners, and the note
    /// that goes with a password prompt, which has its own sheet.
    public static func isChatter(_ raw: String) -> Bool {
        raw.contains("Enter your credentials")
            || ["Clean Your Mac", "Dry Run Mode", "○ DRY RUN MODE", "Optimize"].contains(where: raw.hasPrefix)
    }

    /// Rules and blank frames that carry no information outside a terminal.
    public static func isDecoration(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.allSatisfy { "=-─━".contains($0) }
    }
}
