import Foundation

public enum CommandError: Error, LocalizedError {
    case timedOut
    case failed(status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .timedOut:
            "The command took too long and was stopped."
        case .failed(let status, let message):
            message.isEmpty ? "The command exited with status \(status)." : message
        }
    }
}
