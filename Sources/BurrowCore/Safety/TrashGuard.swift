import Darwin
import Foundation

/// Decides whether a path Analyze shows may be moved to the Trash.
///
/// This is a port of `validateTrashTarget` in Mole's `cmd/analyze/delete.go`. `mo analyze --json`
/// is read-only and the TUI is the CLI's only delete surface, so this app has to apply the
/// same rules itself. Keep the two in step when the Go side changes. The tests in
/// `TrashGuardTests` mirror the cases in `cmd/analyze/delete_test.go`.
public struct TrashGuard: Sendable {
    public enum Refusal: Error, LocalizedError, Equatable {
        case invalidPath(String)
        case protected(String)

        public var errorDescription: String? {
            switch self {
            case .invalidPath(let reason):
                "This path can't be moved to the Trash: \(reason)."
            case .protected(let path):
                "\(path) is protected and can't be moved to the Trash."
            }
        }
    }

    private static let criticalRoots = [
        "/", "/Applications", "/Applications/Finder.app", "/Applications/Safari.app",
        "/Library", "/Library/Apple", "/Library/Application Support", "/Library/Extensions",
        "/Library/Keychains", "/System", "/Users", "/Volumes", "/Network", "/cores", "/dev",
        "/etc", "/home", "/net", "/tmp", "/var", "/private", "/private/etc", "/private/tmp",
        "/private/var", "/private/var/audit", "/private/var/db", "/private/var/root",
        "/private/var/tmp", "/private/var/folders", "/bin", "/sbin", "/usr", "/opt", "/opt/homebrew",
    ]

    private static let protectedTrees = [
        "/System", "/bin", "/sbin", "/usr", "/private/etc", "/private/var/audit", "/private/var/db",
        "/private/var/root", "/Library/Apple", "/Library/Extensions", "/Library/Keychains",
        "/Applications/Finder.app", "/Applications/Safari.app", "/dev",
    ]

    private static let endpointSecurityPrefixes = [
        "com.crowdstrike.", "com.sentinelone.", "com.sentinel-labs.", "com.eset.", "com.jamf.",
        "com.jamfsoftware.", "com.paloaltonetworks.", "com.cisco.anyconnect", "com.cisco.secureclient",
        "com.alibaba.security.",
    ]

    private let homeRoots: [String]

    public init(home: String = NSHomeDirectory()) {
        // Both homes count, as in Go: an overridden HOME must not expose the real one.
        var roots: [String] = []
        var candidates = [home]
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            candidates.append(String(cString: directory))
        }
        for candidate in candidates {
            let cleaned = Self.clean(candidate)
            if !roots.contains(cleaned) { roots.append(cleaned) }
            let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            if !roots.contains(resolved) { roots.append(resolved) }
        }
        homeRoots = roots
    }

    /// Returns normally when the path may be trashed.
    public func validate(_ path: String) throws {
        guard !path.isEmpty else { throw Refusal.invalidPath("it is empty") }
        guard path.hasPrefix("/") else { throw Refusal.invalidPath("it must be absolute") }
        guard !path.contains("\0") else { throw Refusal.invalidPath("it contains a null byte") }
        guard !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            throw Refusal.invalidPath("it contains a parent-directory step")
        }
        if isProtected(path) { throw Refusal.protected(path) }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved != path, isProtected(resolved) { throw Refusal.protected(path) }
    }

    public func isProtected(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let cleanPath = Self.clean(path)
        if Self.isEndpointSecurityCachePath(cleanPath) { return true }
        if Self.isCriticalPath(cleanPath) { return true }

        for home in homeRoots {
            if cleanPath == home || Self.isSameExistingPath(cleanPath, home) { return true }

            let dockerState = home + "/Library/Containers/com.docker.docker"
            if Self.touchesRuntimeRoot(cleanPath, dockerState) { return true }

            let orbstackState = home + "/.orbstack"
            if Self.touchesRuntimeRoot(cleanPath, orbstackState) { return true }

            if Self.isICloudStructuralPath(cleanPath, home: home) { return true }

            let groupContainers = home + "/Library/Group Containers"
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: groupContainers) {
                for entry in entries where entry.lowercased().hasSuffix("dev.orbstack") {
                    let stateRoot = groupContainers + "/" + entry
                    if Self.isPathWithinExistingRoot(cleanPath, stateRoot)
                        || Self.containsProtectedRoot(cleanPath, stateRoot) {
                        return true
                    }
                }
            }
            let lowerContainers = groupContainers.lowercased() + "/"
            let lowerPath = cleanPath.lowercased()
            if lowerPath.hasPrefix(lowerContainers) {
                let relative = lowerPath.dropFirst(lowerContainers.count)
                let container = relative.split(separator: "/").first.map(String.init) ?? ""
                if container.hasSuffix("dev.orbstack") { return true }
            }
        }
        return false
    }

    private static func touchesRuntimeRoot(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
            || isPathWithinExistingRoot(path, root)
            || containsProtectedRoot(path, root)
    }

    private static func isCriticalPath(_ path: String) -> Bool {
        for root in criticalRoots where path == root || isSameExistingPath(path, root) {
            return true
        }
        if isDirectChildOfExistingRoot(path, "/Users") { return true }
        for root in protectedTrees where path.hasPrefix(root + "/") || isPathWithinExistingRoot(path, root) {
            return true
        }
        return false
    }

    /// Mirrors `isICloudStructuralPath`: Mobile Documents, each container in it and a
    /// container's Documents folder. Trashing one removes that store on every device.
    private static func isICloudStructuralPath(_ path: String, home: String) -> Bool {
        let mobileDocuments = home + "/Library/Mobile Documents"
        // A recursive move of an existing ancestor includes the same protected stores.
        if containsProtectedRoot(path, mobileDocuments) { return true }
        // These are directory boundaries, not reserved names for ordinary files.
        var info = stat()
        if stat(path, &info) == 0, (info.st_mode & S_IFMT) != S_IFDIR { return false }

        let lowerRoot = mobileDocuments.lowercased()
        let lowerPath = path.lowercased()
        if lowerPath == lowerRoot { return true }
        guard lowerPath.hasPrefix(lowerRoot + "/") else {
            return isICloudStructuralByIdentity(path, mobileDocuments)
        }
        let parts = lowerPath.dropFirst(lowerRoot.count + 1).split(separator: "/")
        switch parts.count {
        case 1: return true
        case 2: return parts[1] == "documents"
        default: return false
        }
    }

    /// Applies the same depth rule when the path names Mobile Documents another way,
    /// such as through `/System/Volumes/Data` or a symlinked parent.
    private static func isICloudStructuralByIdentity(_ path: String, _ mobileDocuments: String) -> Bool {
        guard fileIdentity(mobileDocuments) != nil else { return false }
        if isSameExistingPath(path, mobileDocuments) { return true }
        let parent = parentPath(path)
        if isSameExistingPath(parent, mobileDocuments) { return true }
        return (path as NSString).lastPathComponent.lowercased() == "documents"
            && isSameExistingPath(parentPath(parent), mobileDocuments)
    }

    private static func isEndpointSecurityCachePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        guard lower.hasPrefix("/private/var/folders/") || lower.hasPrefix("/var/folders/") else { return false }
        var relative = lower
        if relative.hasPrefix("/private") { relative.removeFirst("/private".count) }
        relative.removeFirst("/var/folders/".count)
        // A whole Darwin user or cache container also holds any protected agent below it.
        if relative.split(separator: "/", omittingEmptySubsequences: false).count <= 3 { return true }
        return endpointSecurityPrefixes.contains { lower.contains($0) }
    }

    private static func containsProtectedRoot(_ path: String, _ root: String) -> Bool {
        var info = stat()
        if lstat(root, &info) != 0, errno == ENOENT { return false }
        let resolved = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        if isPathWithinExistingRoot(resolved, path) { return true }
        return isPathWithinExistingRoot(root, path)
    }

    private static func isPathWithinExistingRoot(_ path: String, _ root: String) -> Bool {
        guard let rootID = fileIdentity(root) else { return false }
        var current = clean(path)
        while true {
            if fileIdentity(current) == rootID { return true }
            let parent = parentPath(current)
            if parent == current { return false }
            current = parent
        }
    }

    private static func isSameExistingPath(_ path: String, _ other: String) -> Bool {
        guard let first = fileIdentity(path), let second = fileIdentity(other) else { return false }
        return first == second
    }

    private static func isDirectChildOfExistingRoot(_ path: String, _ root: String) -> Bool {
        let parent = parentPath(path)
        return path != clean(root) && parent != path && isSameExistingPath(parent, root)
    }

    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static func fileIdentity(_ path: String) -> FileIdentity? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileIdentity(device: info.st_dev, inode: info.st_ino)
    }

    private static func parentPath(_ path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    private static func clean(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        // standardizingPath strips /private from some paths, which the guard must see.
        if path.hasPrefix("/private/") { return trimTrailingSlash(path) }
        return trimTrailingSlash(standardized)
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }
}
