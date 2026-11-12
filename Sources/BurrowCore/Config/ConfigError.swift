import Foundation

public enum ConfigError: Error, LocalizedError, Equatable {
    case unreadable(String)
    case defaultsUnavailable
    case invalidPattern(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            "\(name) couldn't be read as text, so it was left unchanged."
        case .defaultsUnavailable:
            "Mole's default protections couldn't be read from the CLI, so saving now would drop them."
        case .invalidPattern(let reason):
            reason
        }
    }
}
