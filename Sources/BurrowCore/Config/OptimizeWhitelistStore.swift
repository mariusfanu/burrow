import Foundation

/// `~/.config/mole/whitelist_optimize`: optimize tasks the CLI should skip.
public struct OptimizeWhitelistStore: Sendable {
    public struct Task: Identifiable, Sendable, Equatable {
        public let name: String
        public let action: String
        public var id: String { action }
    }

    private let fileURL: URL
    /// The older name the CLI still reads when the current file is absent. Saving creates
    /// the current file, which the CLI then prefers, so this one's entries must carry over.
    private let legacyURL: URL
    private let cliRoot: String?

    public init(home: String = NSHomeDirectory(), cliRoot: String?) {
        fileURL = URL(fileURLWithPath: home + "/.config/mole/whitelist_optimize")
        legacyURL = URL(fileURLWithPath: home + "/.config/mole/whitelist_checks")
        self.cliRoot = cliRoot
    }

    public func load() throws -> Set<String> {
        guard let text = try ConfigFile.read(fileURL) ?? ConfigFile.read(legacyURL) else { return [] }
        return Set(ConfigFile.parseList(text))
    }

    public func save(_ actions: Set<String>) throws {
        try save(actions, replacing: ConfigFile.read(fileURL))
    }

    public func setEnabled(_ enabled: Bool, action: String) throws -> Set<String> {
        let current = try ConfigFile.read(fileURL)
        let legacy = try current == nil ? ConfigFile.read(legacyURL) : nil
        var actions = Set(ConfigFile.parseList(current ?? legacy ?? ""))
        if enabled { actions.remove(action) }
        else { actions.insert(action) }
        if current == nil, try ConfigFile.read(legacyURL) != legacy {
            throw ConfigError.changed(legacyURL.lastPathComponent)
        }
        try save(actions, replacing: current)
        return actions
    }

    private func save(_ actions: Set<String>, replacing previous: String?) throws {
        let header = "# Mole Optimization Whitelist - These checks will be skipped during optimization"
        try ConfigFile.write(([header] + actions.sorted()).joined(separator: "\n") + "\n", to: fileURL, replacing: previous)
    }

    /// Reads the task names and identifiers from the installed CLI's catalog.
    public func availableTasks() -> [Task] {
        guard let cliRoot,
              let source = try? String(contentsOfFile: cliRoot + "/lib/optimize/catalog.sh", encoding: .utf8) else {
            return []
        }
        return Self.parseTasks(source)
    }

    /// Parses `_optimize_catalog_register action handler "Health name" "Whitelist name" ...`.
    static func parseTasks(_ source: String) -> [Task] {
        let pattern = /_optimize_catalog_register\s+(\w+)\s+\w+\s*\\\s*"[^"]*"\s+"([^"]*)"/
        return source.matches(of: pattern).map { Task(name: String($0.2), action: String($0.1)) }
    }
}
