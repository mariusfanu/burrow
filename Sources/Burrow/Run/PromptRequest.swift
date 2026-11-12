import BurrowCore
import Foundation

/// A question from the CLI, presented as a native sheet.
struct PromptRequest: Identifiable, Equatable {
    let id = UUID()
    let prompt: CLIPrompt
}
