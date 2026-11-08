import Foundation

/// One row of `mo uninstall --list`.
public struct InstalledApp: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public var name: String
    public var bundleId: String?
    public var source: String?
    public var uninstallName: String
    public var path: String?
    public var size: String?

    public var id: String { path ?? uninstallName }

    public static func decodeList(_ data: Data) throws -> [InstalledApp] {
        // Rows with the same identity can't be told apart, and the list needs unique IDs.
        var seen = Set<String>()
        return try JSONDecoder.forCLI().decode([InstalledApp].self, from: data).filter { seen.insert($0.id).inserted }
    }
}
