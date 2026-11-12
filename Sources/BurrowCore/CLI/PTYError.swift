import Foundation

public enum PTYError: Error, LocalizedError {
    case spawnFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .spawnFailed(let code):
            "Could not start the command: \(String(cString: strerror(code)))"
        }
    }
}
