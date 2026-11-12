import Foundation

public extension String {
    /// True for a progress line: the CLI draws its spinner from the Braille block.
    var startsWithSpinner: Bool {
        unicodeScalars.first.map { (0x2800...0x28FF).contains($0.value) } ?? false
    }
}

public enum PromptDetector {
    nonisolated(unsafe) private static let sudoPassword = /(?i)^(\[sudo\] )?password( for [^:]*)?:$/
    nonisolated(unsafe) private static let yesNoPattern = /(\[y\/N\]|\[Y\/n\]|\(y\/n\))\s*:?$/
    nonisolated(unsafe) private static let confirmPattern = /Enter\b.*\b(confirm|enable|disable|continue)\b.*\b(cancel|quit)\s*:$/

    /// Recognizes a prompt on the unfinished line. Prompts never end in a newline,
    /// so a printed line of ordinary output can never be mistaken for one.
    public static func detect(partial: String) -> CLIPrompt? {
        let text = partial.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        // A spinner line can quote any path, so it's progress even if the words match.
        if text.startsWithSpinner { return nil }

        if text.hasPrefix("➤ System caches need sudo"), text.contains("Enter"), text.hasSuffix(":") {
            return .systemCleanChoice
        }
        // The whole line must be the prompt, because a progress line can end in a path
        // named `password:`. The caller must also confirm that echo is off.
        if text.firstMatch(of: sudoPassword) != nil {
            return .password(text)
        }
        if text.firstMatch(of: yesNoPattern) != nil {
            return .yesNo(cleanIcon(text))
        }
        if text.firstMatch(of: confirmPattern) != nil {
            return .confirm(cleanIcon(text))
        }
        return nil
    }

    private static func cleanIcon(_ text: String) -> String {
        var result = text
        for icon in ["➤", "◎"] where result.hasPrefix(icon) {
            result = String(result.dropFirst(icon.count)).trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}
