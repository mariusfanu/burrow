import Foundation

/// Chooses the words to pass to `mo uninstall`, which names apps but not their locations.
///
/// `match_apps_by_name` in `bin/uninstall.sh` takes the first app whose display name or
/// `.app` folder name equals a word. Two apps can share a display name, as `Xcode.app` and
/// `Xcode-beta.app` do, and `uninstall_name` can be a Homebrew cask that matches neither.
public enum UninstallTargeting {
    /// One word per app, preferring a word only that app answers to. An app with no such
    /// word gets a usable fallback, and `UninstallPlan` then checks which app the CLI chose.
    /// An app with no safe positional spelling produces no term.
    public static func terms(for selected: [InstalledApp], among all: [InstalledApp]) -> [String] {
        guard !selected.isEmpty else { return [] }
        // Count how many apps in `all` match each name or folder once, so unique checks are O(1).
        var wordCounts: [String: (count: Int, id: InstalledApp.ID)] = [:]
        for app in all {
            let name = app.name.lowercased()
            let folder = folderName(of: app)?.lowercased()
            var words = [name]
            if let folder, folder != name {
                words.append(folder)
            }
            for word in words {
                if let existing = wordCounts[word] {
                    wordCounts[word] = (existing.count + 1, existing.id)
                } else {
                    wordCounts[word] = (1, app.id)
                }
            }
        }
        return selected.compactMap { app in
            let candidates = [app.uninstallName, app.name, folderName(of: app)].compactMap { $0 }
                .filter { !$0.isEmpty && !$0.hasPrefix("-") && !$0.utf8.contains(0) }
            let unique = candidates.first { candidate in
                let word = candidate.lowercased()
                guard let match = wordCounts[word] else { return false }
                return match.count == 1 && match.id == app.id
            }
            return unique ?? folderName(of: app).flatMap { candidates.contains($0) ? $0 : nil } ?? candidates.first
        }
    }

    private static func folderName(of app: InstalledApp) -> String? {
        guard let path = app.path else { return nil }
        let name = (path as NSString).lastPathComponent
        return name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
