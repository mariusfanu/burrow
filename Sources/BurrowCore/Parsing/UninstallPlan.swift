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
        for line in lines[(start + 1)...] {
            guard line.hasPrefix(" ") else {
                awaitingPath = line.hasPrefix("◎ ")
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard awaitingPath, trimmed.hasPrefix("✓ ") else { continue }
            awaitingPath = false
            var path = String(trimmed.dropFirst(2))
            if let size = path.range(of: " , ", options: .backwards) { path = String(path[..<size.lowerBound]) }
            if path == "~" || path.hasPrefix("~/") { path = home + path.dropFirst() }
            paths.insert(path)
        }
        return paths
    }
}
