import Darwin
import Foundation

/// Decides which allowed paths deserve a second look before they go to the Trash.
///
/// `TrashGuard` mirrors what the CLI refuses outright, and it allows paths such as `~/.ssh`
/// and `~/Library/Keychains`. The CLI asks before every move, but Burrow asks only when a move
/// is likely to be a mistake, so that ordinary files keep the Finder's one-click behavior.
/// This is Burrow's own judgment rather than a port, and it never makes a path refusable.
public struct TrashRisk: Sendable {
    public enum Reason: Sendable, Equatable, CaseIterable {
        case credentials
        case iCloud
        case appData
        case topLevelFolder
        case outsideHome
    }

    private static let credentialFolders: Set<String> = [
        ".ssh", ".gnupg", ".aws", ".azure", ".kube", ".password-store",
    ]
    private static let sensitiveLibraryFolders: Set<String> = [
        "accounts", "calendars", "containers", "cookies", "group containers", "launchagents",
        "mail", "messages", "preferences", "safari",
    ]
    /// Scratch space, where nothing outlives its purpose.
    private static let scratchRoots = ["/tmp", "/private/tmp", "/var/folders", "/private/var/folders"]

    private let homes: [String]

    public init(home: String = NSHomeDirectory()) {
        // Both homes count, as in `TrashGuard`, because `HOME` can be overridden.
        var candidates = [home]
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            candidates.append(String(cString: directory))
        }
        var roots: [String] = []
        for candidate in candidates {
            for root in [candidate, URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path] {
                let lowered = Self.normalized(root)
                if !roots.contains(lowered) { roots.append(lowered) }
            }
        }
        homes = roots
    }

    /// Why this path deserves a second look, or nil if it doesn't. This resolves the parent
    /// folder, because a path can reach a sensitive place through a link. The item's own link
    /// isn't followed, because moving a link leaves its target where it is.
    public func reason(forPath path: String, isDirectory: Bool) -> Reason? {
        if let reason = Self.reason(forNormalized: Self.normalized(path), isDirectory: isDirectory, homes: homes) {
            return reason
        }
        let url = URL(fileURLWithPath: path)
        let resolved = url.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent).path
        return Self.reason(forNormalized: Self.normalized(resolved), isDirectory: isDirectory, homes: homes)
    }

    private static func reason(forNormalized path: String, isDirectory: Bool, homes: [String]) -> Reason? {
        for home in homes where path.hasPrefix(home + "/") {
            let parts = path.dropFirst(home.count + 1).split(separator: "/")
            return reason(inHome: parts, isDirectory: isDirectory)
        }
        return reason(outsideHome: path)
    }

    private static func reason(inHome parts: [Substring], isDirectory: Bool) -> Reason? {
        guard let first = parts.first else { return nil }
        if first == "library" {
            guard parts.count > 1 else { return .appData }
            if parts[1] == "mobile documents" { return .iCloud }
            if parts[1] == "keychains" { return .credentials }
            return parts.count == 2 || sensitiveLibraryFolders.contains(String(parts[1])) ? .appData : nil
        }
        if credentialFolders.contains(String(first)) { return .credentials }
        if first == ".config" { return .appData }
        guard parts.count == 1 else { return nil }
        if first.hasPrefix(".") { return .appData }
        return isDirectory ? .topLevelFolder : nil
    }

    private static func reason(outsideHome path: String) -> Reason? {
        if scratchRoots.contains(where: { path.hasPrefix($0 + "/") }) { return nil }
        let parts = path.split(separator: "/")
        // Files on another disk are ordinary, but the disk itself isn't.
        if parts.first == "volumes" { return parts.count > 2 ? nil : .outsideHome }
        // A third-party app sits at the top of /Applications. Removing one is routine.
        if parts.count == 2, parts[0] == "applications", parts[1].hasSuffix(".app") { return nil }
        return .outsideHome
    }

    private static func normalized(_ path: String) -> String {
        var result = path.lowercased()
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }
}
