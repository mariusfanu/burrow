import Foundation

/// A located copy of the Mole CLI.
public struct CLIInfo: Sendable, Equatable {
    public let executable: String
    public let root: String
    public let version: String
    public let installMethod: String

    public init(executable: String, root: String, version: String, installMethod: String) {
        self.executable = executable
        self.root = root
        self.version = version
        self.installMethod = installMethod
    }

    /// The Go status and analyze binaries ship with releases, not with a source checkout.
    public var hasBundledTools: Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: root + "/bin/status-go")
            && fileManager.fileExists(atPath: root + "/bin/analyze-go")
    }
}

public enum CLILocator {
    public static let customPathKey = "cliPath"

    /// Directories a Finder-launched app needs on PATH. A GUI app inherits only
    /// `/usr/bin:/bin:/usr/sbin:/sbin`, which would hide `brew` and developer tools
    /// from the cleanup sections that call them.
    private static var searchDirectories: [String] {
        let home = NSHomeDirectory()
        return [
            "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/local/bin", "/usr/local/sbin",
            home + "/.local/bin", home + "/bin",
            home + "/.nix-profile/bin", "/run/current-system/sw/bin",
            home + "/.cargo/bin", home + "/.bun/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
    }

    /// Where the system's own tools live, which come first on a command's PATH. Burrow hands
    /// passwords to whichever `sudo` the CLI finds, so a program in a folder the user can
    /// write to, such as `~/.local/bin`, must not be able to stand in for it.
    private static let systemDirectories = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    public static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        let inherited = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        environment["PATH"] = (systemDirectories + searchDirectories + inherited).filter { seen.insert($0).inserted }.joined(separator: ":")
        environment["LANG"] = base["LANG"] ?? "en_US.UTF-8"
        environment["LC_CTYPE"] = base["LC_CTYPE"] ?? "en_US.UTF-8"
        return environment
    }

    /// Finds `mo`, preferring an explicitly chosen path.
    private static func candidatePaths(customPath: String?) -> [String] {
        var candidates: [String] = []
        if let customPath, !customPath.isEmpty { candidates.append(customPath) }
        #if DEBUG
        // Debug only: in a release build this would let the environment choose what Burrow runs.
        if let override = ProcessInfo.processInfo.environment["BURROW_CLI"], !override.isEmpty {
            candidates.insert(override, at: 0)
        }
        #endif
        for directory in searchDirectories {
            candidates.append(directory + "/mo")
            candidates.append(directory + "/mole")
        }
        return candidates
    }

    public static func locate(customPath: String?) async -> CLIInfo? {
        let fileManager = FileManager.default
        for path in candidatePaths(customPath: customPath)
        where fileManager.isExecutableFile(atPath: path) && isSafeToRun(path) {
            let result = try? await CommandRunner.run(executable: path, arguments: ["--version"], timeout: 15)
            guard let result, result.status == 0, let info = parseVersionOutput(result.stdout, executable: path) else {
                continue
            }
            return info
        }
        return nil
    }

    /// Skips a program that another account could have changed, since discovery runs each
    /// candidate and whichever is chosen receives passwords. Follows symlinks.
    static func isSafeToRun(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        let ownerIsTrusted = info.st_uid == 0 || info.st_uid == getuid()
        return ownerIsTrusted && info.st_mode & (S_IWGRP | S_IWOTH) == 0
    }

    /// Parses `mo --version`, which prints `Mole version x.y.z` and `Install: ...`.
    static func parseVersionOutput(_ output: String, executable: String) -> CLIInfo? {
        let lines = ANSI.strip(output).split(whereSeparator: \.isNewline).map(String.init)
        guard let versionLine = lines.first(where: { $0.hasPrefix("Mole version ") }) else { return nil }
        let version = String(versionLine.dropFirst("Mole version ".count)).trimmingCharacters(in: .whitespaces)
        let method = lines.first { $0.hasPrefix("Install:") }
            .map { $0.dropFirst("Install:".count).trimmingCharacters(in: .whitespaces) } ?? "Unknown"
        return CLIInfo(
            executable: executable,
            root: resolveRoot(of: executable),
            version: version,
            installMethod: method
        )
    }

    nonisolated(unsafe) private static let wrapperPattern = /(\/[^\s"']+)\/mole\b/

    /// Finds the directory holding `lib/`, following the Homebrew wrapper when needed.
    static func resolveRoot(of executable: String) -> String {
        let fileManager = FileManager.default
        let resolved = URL(fileURLWithPath: executable).resolvingSymlinksInPath()
        let direct = resolved.deletingLastPathComponent().path
        if fileManager.fileExists(atPath: direct + "/lib/core/base.sh") { return direct }

        // A Homebrew prefix keeps the tree in libexec beside its bin directory.
        let prefix = resolved.deletingLastPathComponent().deletingLastPathComponent().path
        for candidate in [prefix + "/libexec", prefix + "/lib/mole", prefix + "/share/mole"]
        where fileManager.fileExists(atPath: candidate + "/lib/core/base.sh") {
            return candidate
        }
        // A generated wrapper script names its target with an absolute path.
        if let script = try? String(contentsOf: resolved, encoding: .utf8) {
            for match in script.matches(of: wrapperPattern) {
                let candidate = String(match.1)
                if fileManager.fileExists(atPath: candidate + "/lib/core/base.sh") { return candidate }
            }
        }
        return direct
    }
}
