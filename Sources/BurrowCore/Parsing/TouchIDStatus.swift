import Foundation

/// What `mo touchid status` printed, or nil if it printed nothing.
public struct TouchIDStatus: Sendable, Equatable {
    public let description: String
    public let isEnabled: Bool

    public init?(output: String) {
        let text = ANSI.strip(output).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let first = text.first, "◎✓○".contains(first) {
            description = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else {
            description = text
        }
        isEnabled = !text.lowercased().contains("not ")
    }
}
