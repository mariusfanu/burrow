import Foundation

/// `~/.config/mole/whitelist_optimize`: optimize tasks the CLI should skip.
public struct OptimizeWhitelistStore: Sendable {
    public struct Snapshot: Sendable {
        fileprivate let text: String?
        fileprivate let legacyText: String?
        public var actions: Set<String> {
            guard let effective = text ?? legacyText else { return [] }
            return Set(ConfigFile.parseList(effective))
        }
    }

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
        try snapshot().actions
    }

    public func snapshot() throws -> Snapshot {
        let text = try ConfigFile.read(fileURL)
        let legacyText = text == nil ? try ConfigFile.read(legacyURL) : nil
        return Snapshot(text: text, legacyText: legacyText)
    }

    public func save(_ actions: Set<String>) throws {
        try save(actions, replacing: snapshot())
    }

    public func setEnabled(_ enabled: Bool, action: String) throws -> Set<String> {
        let current = try snapshot()
        var actions = current.actions
        if enabled { actions.remove(action) }
        else { actions.insert(action) }
        try save(actions, replacing: current)
        return actions
    }

    public func save(_ actions: Set<String>, replacing previous: Snapshot) throws {
        if previous.text == nil, try ConfigFile.read(legacyURL) != previous.legacyText {
            throw ConfigError.changed(legacyURL.lastPathComponent)
        }
        try ConfigFile.validateEntries(
            actions,
            message: "An optimization action can't start with # or contain control characters."
        )
        let header = "# Mole Optimization Whitelist - These checks will be skipped during optimization"
        try ConfigFile.write(([header] + actions.sorted()).joined(separator: "\n") + "\n", to: fileURL, replacing: previous.text)
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
        let pattern = /_optimize_catalog_register\s+(\w+)\s+\w+(?:\s*\\\s*|\s+)"[^"]*"\s+"([^"]*)"/
        return source.matches(of: pattern).map { Task(name: String($0.2), action: String($0.1)) }
    }
}
