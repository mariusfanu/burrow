import Foundation

/// A question the CLI is waiting on.
public enum CLIPrompt: Sendable, Equatable {
    /// `sudo` is reading a password from the terminal.
    case password(String)
    /// `mo clean` offers admin access or a skip for the system section.
    case systemCleanChoice
    /// Enter confirms and Esc (or Q) cancels. Holds the CLI's own question.
    case confirm(String)
    /// A `[y/N]` question.
    case yesNo(String)
}

public extension CLIPrompt {
    nonisolated(unsafe) private static let enterConfirmTrailing = /\s+Enter confirm.*$/

    /// Turns `Remove 1 app, 682.6MB  Enter confirm, ESC cancel:` into its question.
    static func question(from text: String) -> String {
        var result = text
        for marker in ["  Enter confirm", " Enter confirm", "Press Enter to"] {
            if let range = result.range(of: marker) {
                let before = result[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                if !before.isEmpty {
                    result = before
                    break
                }
                let action = result[range.upperBound...]
                    .components(separatedBy: ",")[0]
                    .trimmingCharacters(in: .whitespaces)
                result = action.prefix(1).uppercased() + action.dropFirst()
                break
            }
        }
        result = result.replacing(enterConfirmTrailing, with: "")
        return result.hasSuffix(":") ? String(result.dropLast()) : result
    }

    /// A specific verb for the button, taken from the CLI's own question.
    static func confirmTitle(from text: String) -> String {
        let question = question(from: text)
        let known = ["Remove", "Delete", "Slim", "Enable", "Disable", "Uninstall", "Purge", "Clean", "Update"]
        if let first = question.split(separator: " ").first.map(String.init), known.contains(first) {
            return first
        }
        return "Confirm"
    }
}
