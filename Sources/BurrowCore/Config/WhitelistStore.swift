import Foundation

/// The CLI's protected-path list at `~/.config/mole/whitelist`.
///
/// A saved file replaces the optional default patterns rather than adding to them. Adding
/// one path to a file that doesn't exist yet would silently drop every default, so the
/// first save writes the defaults too. `FINDER_METADATA` is a sentinel the CLI understands.
public struct WhitelistStore: Sendable {
    private let fileURL: URL
    private let home: String
    private let cliRoot: String?

    /// Read from the installed CLI on demand: only a missing whitelist file needs them.
    private var defaults: [String] { Self.readDefaults(cliRoot: cliRoot, home: home) }

    public init(home: String = NSHomeDirectory(), cliRoot: String?) {
        self.home = home
        self.cliRoot = cliRoot
        fileURL = URL(fileURLWithPath: home + "/.config/mole/whitelist")
    }

    public var usesDefaults: Bool {
        !FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// The patterns in effect now. Throws if the file exists but can't be understood,
    /// because treating it as empty would lose the user's protections on the next save.
    public func load() throws -> [String] {
        guard let text = try ConfigFile.read(fileURL) else { return defaults }
        return Self.parse(text)
    }

    public func save(_ patterns: [String]) throws {
        // A first save writes the defaults, so they have to be known.
        if usesDefaults, defaults.isEmpty { throw ConfigError.defaultsUnavailable }

        var seen = Set<String>()
        let unique = patterns
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let header = """
        # Mole Whitelist - Protected paths won't be deleted
        # Saved selections replace optional defaults; built-in safety protections still apply.
        # Add one pattern per line to keep items safe.
        """
        try ConfigFile.write(([header] + unique).joined(separator: "\n") + "\n", to: fileURL)
    }

    public func add(_ pattern: String) throws {
        if let problem = Self.problem(with: pattern, home: home) { throw ConfigError.invalidPattern(problem) }
        try save(load() + [pattern])
    }

    public func remove(_ pattern: String) throws {
        try save(load().filter { $0 != pattern })
    }

    public static func parse(_ text: String) -> [String] {
        ConfigFile.parseList(text)
    }

    /// Mirrors the checks in `load_whitelist` (`lib/core/base.sh`), which silently ignore
    /// a bad entry. Saving one would look like protection while providing none.
    public static func problem(with pattern: String, home: String) -> String? {
        guard pattern != "FINDER_METADATA" else { return nil }
        var expanded = pattern
        if expanded.hasPrefix("~") { expanded = home + expanded.dropFirst() }
        expanded = expanded
            .replacing("${HOME}", with: home)
            .replacing("$HOME", with: home)
        if expanded.contains("..") { return "Mole doesn't accept “..” in a protected path." }
        if expanded.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            return "A protected path can't contain control characters."
        }
        if !expanded.hasPrefix("/") { return "A protected path has to start with / or ~/." }
        if expanded.contains("//") { return "Mole doesn't accept consecutive slashes in a protected path." }
        let systemRoots = ["/System", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/etc", "/var/db"]
        if expanded == "/" || systemRoots.contains(where: { expanded == $0 || expanded.hasPrefix($0 + "/") }) {
            return "System paths are always protected, so Mole ignores them here."
        }
        return nil
    }

    /// Reads `DEFAULT_WHITELIST_PATTERNS` from the installed CLI so this can't go stale.
    static func readDefaults(cliRoot: String?, home: String) -> [String] {
        guard let cliRoot,
              let source = try? String(contentsOfFile: cliRoot + "/lib/core/base.sh", encoding: .utf8) else {
            return []
        }
        return parseDefaults(fromBaseScript: source, home: home)
    }

    static func parseDefaults(fromBaseScript source: String, home: String) -> [String] {
        guard let start = source.range(of: "declare -a DEFAULT_WHITELIST_PATTERNS=("),
              let end = source.range(of: "\n)", range: start.upperBound..<source.endIndex) else {
            return []
        }
        return source[start.upperBound..<end.lowerBound]
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else { return nil }
                return String(trimmed.dropFirst().dropLast())
                    .replacing("$HOME", with: home)
                    .replacing("$FINDER_METADATA_SENTINEL", with: "FINDER_METADATA")
            }
    }
}
