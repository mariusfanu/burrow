import Foundation

/// How a CLI's version compares to the one Burrow was last checked against.
///
/// Menus and prompts fail safely on a different CLI, but Burrow's copy of the Trash rules
/// can't notice a rule it doesn't have, so a difference is worth saying out loud.
public enum CLICompatibility: Equatable, Sendable {
    case checked
    case newer
    case older
    case unknown

    /// Update this after checking a new release, along with the README's compatibility notes.
    public static let checkedVersion = "1.70.0"

    public init(version: String, checkedVersion: String = CLICompatibility.checkedVersion) {
        guard let found = Self.components(version), let checked = Self.components(checkedVersion) else {
            self = .unknown
            return
        }
        for index in 0..<max(found.count, checked.count) {
            let foundPart = index < found.count ? found[index] : 0
            let checkedPart = index < checked.count ? checked[index] : 0
            if foundPart != checkedPart {
                self = foundPart > checkedPart ? .newer : .older
                return
            }
        }
        self = .checked
    }

    /// What to tell the user, or nil when there's nothing to say.
    public func warning(version: String) -> String? {
        let checked = "Burrow was last checked with Mole \(Self.checkedVersion)"
        switch self {
        case .checked:
            return nil
        case .newer:
            return "\(checked), and this is \(version). Some screens may not work, and Disk Explorer may not know about paths Mole newly protects."
        case .older:
            return "\(checked), and this is \(version). Updating Mole is recommended."
        case .unknown:
            return "\(checked), and couldn’t compare this version (\(version)). Some screens may not work."
        }
    }

    /// Numeric parts of `1.69.0` or `v1.69`. Anything else, such as a nightly label, is nil.
    private static func components(_ version: String) -> [Int]? {
        let trimmed = version.hasPrefix("v") || version.hasPrefix("V") ? version.dropFirst() : version[...]
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var result: [Int] = []
        result.reserveCapacity(parts.count)
        for part in parts {
            guard let number = Int(part) else { return nil }
            result.append(number)
        }
        return result
    }
}
