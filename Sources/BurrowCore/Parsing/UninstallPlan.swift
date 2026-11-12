import Foundation

/// Reads which apps `mo uninstall` is about to remove, from the plan it prints before asking.
public enum UninstallPlan {
    /// The plan lists each app as an unindented `◎ Name , size`, followed by indented notes
    /// and then `  ✓ path , size`. Returns nothing if no plan is found, which a caller must
    /// treat as a mismatch, because the wording of the plan may have changed.
    public static func appPaths(in lines: [String], home: String) -> Set<String> {
        guard let start = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "Files to be removed:" }) else {
            return []
        }
        var paths = Set<String>()
        var awaitingPath = false
        var readingApps = true
        for line in lines[(start + 1)...] {
            if line.hasPrefix("◎ ") {
                guard readingApps, !awaitingPath else { return [] }
                awaitingPath = true
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !line.hasPrefix(" ") {
                guard !awaitingPath else { return [] }
                readingApps = false
            }
            guard awaitingPath, line.hasPrefix(" "), trimmed.hasPrefix("✓ ") else { continue }
            awaitingPath = false
            var path = String(trimmed.dropFirst(2))
            if let size = path.range(of: " , ", options: .backwards) { path = String(path[..<size.lowerBound]) }
            if path == "~" || path.hasPrefix("~/") { path = home + path.dropFirst() }
            guard path.hasPrefix("/"), paths.insert(path).inserted else { return [] }
        }
        return awaitingPath ? [] : paths
    }

    public static func appCount(in prompt: CLIPrompt) -> Int? {
        guard case .confirm(let text) = prompt else { return nil }
        let parts = CLIPrompt.question(from: text).split(separator: " ", maxSplits: 3)
        guard parts.count >= 3, parts[0] == "Remove",
              ["app", "app,", "apps", "apps,"].contains(parts[2]) else { return nil }
        return Int(parts[1])
    }
}
