import Foundation

/// `~/.config/mole/purge_paths`: where `mo purge` looks for projects.
public struct PurgePathsStore: Sendable {
    private let fileURL: URL

    public init(home: String = NSHomeDirectory()) {
        fileURL = URL(fileURLWithPath: home + "/.config/mole/purge_paths")
    }

    public func load() throws -> [String] {
        guard let text = try ConfigFile.read(fileURL) else { return [] }
        return WhitelistStore.parse(text)
    }

    public func save(_ paths: [String]) throws {
        let header = """
        # Mole Purge Paths - Auto-discovered project directories
        # Edit this file to customize, or run: mo purge --paths
        # Add one path per line (supports ~ for home directory)
        """
        try ConfigFile.write(([header, ""] + paths).joined(separator: "\n") + "\n", to: fileURL)
    }
}
