import Foundation

public enum MenuDriverError: Error, LocalizedError, Equatable {
    case menuDidNotAppear
    case menuClosed
    case rowMismatch(expected: String, found: String)
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .menuDidNotAppear:
            "The command didn't show its selection list in time."
        case .menuClosed:
            "The selection list closed unexpectedly. Nothing was confirmed."
        case .rowMismatch(let expected, let found):
            "The list changed while selecting (expected “\(expected)”, found “\(found)”). Nothing was confirmed."
        case .verificationFailed(let reason):
            "The selection couldn't be verified: \(reason). Nothing was confirmed."
        }
    }
}
