import Foundation

/// `~/.config/mole/purge_paths`: where `mo purge` looks for projects.
public struct PurgePathsStore: Sendable {
    public struct Snapshot: Sendable {
        fileprivate let text: String?
        public var paths: [String] { ConfigFile.parseList(text ?? "") }
    }

    private let fileURL: URL

    public init(home: String = NSHomeDirectory()) {
        fileURL = URL(fileURLWithPath: home + "/.config/mole/purge_paths")
    }

    public func load() throws -> [String] {
        try snapshot().paths
    }

    public func snapshot() throws -> Snapshot {
        try Snapshot(text: ConfigFile.read(fileURL))
    }

    public func save(_ paths: [String]) throws {
        try save(paths, replacing: snapshot())
    }

    public func save(_ paths: [String], replacing previous: Snapshot) throws {
        try ConfigFile.validateEntries(
            paths,
            message: "A purge path can't start with # or contain control characters."
        )
        let header = """
        # Mole Purge Paths - Auto-discovered project directories
        # Edit this file to customize, or run: mo purge --paths
        # Add one path per line (supports ~ for home directory)
        """
        try ConfigFile.write(([header, ""] + paths).joined(separator: "\n") + "\n", to: fileURL, replacing: previous.text)
    }
}
