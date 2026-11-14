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
        if let accountHome = accountHomeDirectory() { candidates.append(accountHome) }
        for candidate in candidates {
            let cleaned = Self.clean(candidate)
            if !roots.contains(cleaned) { roots.append(cleaned) }
            let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            if !roots.contains(resolved) { roots.append(resolved) }
        }
        homeRoots = roots
    }

    /// Returns normally when the path may be trashed. All filesystem reads are fresh.
    public func validate(_ path: String) throws {
        var inspection = Inspection(homeRoots: homeRoots, cache: nil)
        try inspection.validate(path)
    }

    public func isProtected(_ path: String) -> Bool {
        var inspection = Inspection(homeRoots: homeRoots, cache: nil)
        return inspection.isProtected(path)
    }

    /// A display snapshot. Each actual move must call validate again.
    public func protectedPaths(_ paths: some Sequence<String>) throws -> Set<String> {
        var inspection = Inspection(homeRoots: homeRoots, cache: Inspection.Cache())
        var protected: Set<String> = []
        for path in paths {
            try Task.checkCancellation()
            do { try inspection.validate(path) }
            catch { protected.insert(path) }
        }
        return protected
    }

    private struct Inspection {
        struct Cache {
            var metadata: [String: FileMetadata?] = [:]
            var roots: [String: String?] = [:]
            var orbStackRoots: [String: [String]] = [:]
            var ancestorIdentities: [String: Set<FileIdentity>] = [:]
        }

        let homeRoots: [String]
        var cache: Cache?

        /// Returns normally when the path may be trashed.
        mutating func validate(_ path: String) throws {
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

        mutating func isProtected(_ path: String) -> Bool {
            guard !path.isEmpty else { return false }
            let cleanPath = TrashGuard.clean(path)
            if TrashGuard.isEndpointSecurityCachePath(cleanPath) { return true }
            if isCriticalPath(cleanPath) { return true }

            for home in homeRoots {
                if cleanPath.lowercased() == home.lowercased() || isSameExistingPath(cleanPath, home) { return true }

                let dockerState = home + "/Library/Containers/com.docker.docker"
                if touchesRuntimeRoot(cleanPath, dockerState) { return true }

                let orbstackState = home + "/.orbstack"
                if touchesRuntimeRoot(cleanPath, orbstackState) { return true }

                if isICloudStructuralPath(cleanPath, home: home) { return true }

                let groupContainers = home + "/Library/Group Containers"
                for root in orbStackRoots(in: groupContainers) {
                    if isPathWithinExistingRoot(cleanPath, root) || containsProtectedRoot(cleanPath, root) {
                        return true
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

        private mutating func touchesRuntimeRoot(_ path: String, _ root: String) -> Bool {
            let lowerPath = path.lowercased()
            let lowerRoot = root.lowercased()
            return lowerPath == lowerRoot || lowerPath.hasPrefix(lowerRoot + "/")
                || isPathWithinExistingRoot(path, root)
                || containsProtectedRoot(path, root)
        }

        private mutating func isCriticalPath(_ path: String) -> Bool {
            let lowerPath = path.lowercased()
            for root in TrashGuard.criticalRoots {
                if lowerPath == root.lowercased() || isSameExistingPath(path, root) { return true }
            }
            if isDirectChildOfExistingRoot(path, "/Users") { return true }
            for root in TrashGuard.protectedTrees {
                if lowerPath.hasPrefix(root.lowercased() + "/") || isPathWithinExistingRoot(path, root) { return true }
            }
            return false
        }

        /// Mirrors `isICloudStructuralPath`: Mobile Documents, each container in it and a
        /// container's Documents folder. Trashing one removes that store on every device.
        private mutating func isICloudStructuralPath(_ path: String, home: String) -> Bool {
            let mobileDocuments = home + "/Library/Mobile Documents"
            // A recursive move of an existing ancestor includes the same protected stores.
            if containsProtectedRoot(path, mobileDocuments) { return true }
            // These are directory boundaries, not reserved names for ordinary files.
            if let info = metadata(path), (info.mode & S_IFMT) != S_IFDIR { return false }

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
        private mutating func isICloudStructuralByIdentity(_ path: String, _ mobileDocuments: String) -> Bool {
            guard fileIdentity(mobileDocuments) != nil else { return false }
            if isSameExistingPath(path, mobileDocuments) { return true }
            let parent = TrashGuard.parentPath(path)
            if isSameExistingPath(parent, mobileDocuments) { return true }
            return (path as NSString).lastPathComponent.lowercased() == "documents"
                && isSameExistingPath(TrashGuard.parentPath(parent), mobileDocuments)
        }

        private mutating func containsProtectedRoot(_ path: String, _ root: String) -> Bool {
            guard let resolved = existingRoot(root) else { return false }
            if isPathWithinExistingRoot(resolved, path) { return true }
            return isPathWithinExistingRoot(root, path)
        }

        private mutating func isPathWithinExistingRoot(_ path: String, _ root: String) -> Bool {
            guard let rootID = fileIdentity(root) else { return false }
            if cache != nil { return identitiesAlongPath(path).contains(rootID) }
            var current = TrashGuard.clean(path)
            while true {
                if fileIdentity(current) == rootID { return true }
                let parent = TrashGuard.parentPath(current)
                if parent == current { return false }
                current = parent
            }
        }

        private mutating func identitiesAlongPath(_ path: String) -> Set<FileIdentity> {
            if let identities = cache?.ancestorIdentities[path] { return identities }
            var identities: Set<FileIdentity> = []
            var current = TrashGuard.clean(path)
            while true {
                if let identity = fileIdentity(current) { identities.insert(identity) }
                let parent = TrashGuard.parentPath(current)
                if parent == current { break }
                current = parent
            }
            cache?.ancestorIdentities[path] = identities
            return identities
        }

        private mutating func isSameExistingPath(_ path: String, _ other: String) -> Bool {
            guard let first = fileIdentity(path), let second = fileIdentity(other) else { return false }
            return first == second
        }

        private mutating func isDirectChildOfExistingRoot(_ path: String, _ root: String) -> Bool {
            let parent = TrashGuard.parentPath(path)
            return path != TrashGuard.clean(root) && parent != path && isSameExistingPath(parent, root)
        }

        private mutating func fileIdentity(_ path: String) -> FileIdentity? {
            metadata(path)?.identity
        }

        private mutating func metadata(_ path: String) -> FileMetadata? {
            if let stored = cache?.metadata[path] { return stored }
            var info = stat()
            let found = stat(path, &info) == 0 ? FileMetadata(info) : nil
            cache?.metadata[path] = .some(found)
            return found
        }

        private mutating func existingRoot(_ path: String) -> String? {
            if let stored = cache?.roots[path] { return stored }
            var info = stat()
            let resolved = lstat(path, &info) != 0 && errno == ENOENT
                ? nil : URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            cache?.roots[path] = .some(resolved)
            return resolved
        }

        private mutating func orbStackRoots(in directory: String) -> [String] {
            if let stored = cache?.orbStackRoots[directory] { return stored }
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            let roots = entries.filter { $0.lowercased().hasSuffix("dev.orbstack") }.map { directory + "/" + $0 }
            cache?.orbStackRoots[directory] = roots
            return roots
        }
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

    private struct FileIdentity: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    private struct FileMetadata {
        let identity: FileIdentity
        let mode: mode_t

        init(_ info: stat) {
            identity = FileIdentity(device: info.st_dev, inode: info.st_ino)
            mode = info.st_mode
        }
    }

    private static func parentPath(_ path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    private static func clean(_ path: String) -> String {
        guard path.hasPrefix("/") else {
            return trimTrailingSlash((path as NSString).standardizingPath)
        }
        // Collapse "//", ".", and ".." lexically while preserving "/private/",
        // which NSString.standardizingPath strips from /private/var, /private/etc, etc.
        var components: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." {
                if !components.isEmpty { components.removeLast() }
            } else {
                components.append(part)
            }
        }
        return "/" + components.joined(separator: "/")
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }
}
