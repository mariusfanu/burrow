import BurrowCore
import Foundation

/// Prepared off the main actor. Rendering and hover never perform filesystem I/O.
struct AnalyzePresentation: Sendable {
    let result: AnalyzeResult
    let entries: [AnalyzeResult.Entry]
    let protectedPaths: Set<String>
    let trashRisks: [String: TrashRisk.Reason]
    let entryPaths: Set<String>

    init(result: AnalyzeResult, protectedPaths: Set<String>, trashRisks: [String: TrashRisk.Reason]) {
        self.result = result
        entries = (result.entries ?? []).sorted {
            $0.size == $1.size ? $0.path < $1.path : $0.size > $1.size
        }
        self.protectedPaths = protectedPaths
        self.trashRisks = trashRisks
        entryPaths = Set(entries.map(\.path))
    }

    /// This folder after some of its items have gone.
    func removing(_ gone: Set<String>) -> AnalyzePresentation {
        var remaining = result
        remaining.entries?.removeAll { gone.contains($0.path) }
        return AnalyzePresentation(
            result: remaining,
            protectedPaths: protectedPaths.subtracting(gone),
            trashRisks: trashRisks.filter { !gone.contains($0.key) }
        )
    }

    static func trashRisks(_ entries: [AnalyzeResult.Entry], home: String) -> [String: TrashRisk.Reason] {
        let risk = TrashRisk(home: home)
        var reasons: [String: TrashRisk.Reason] = [:]
        for entry in entries {
            reasons[entry.path] = risk.reason(forPath: entry.path, isDirectory: entry.isDir)
        }
        return reasons
    }

    static func protectedPaths(_ entries: [AnalyzeResult.Entry], home: String) -> Set<String> {
        let guardrail = TrashGuard(home: home)
        return Set(entries.compactMap { entry in
            do {
                try guardrail.validate(entry.path)
                return nil
            } catch {
                return entry.path
            }
        })
    }
}

/// The question to ask before a selection that includes a high-risk item goes to the Trash.
struct TrashConfirmation: Equatable {
    let paths: Set<String>
    let title: String
    let message: String

    init(selected: [AnalyzeResult.Entry], risks: [String: TrashRisk.Reason]) {
        paths = Set(selected.map(\.path))
        let risky = selected.filter { risks[$0.path] != nil }
        title = selected.count == 1
            ? "Move “\(selected[0].name)” to the Trash?"
            : "Move \(selected.count) Items to the Trash?"

        var parts: [String] = []
        if selected.count > 1 {
            let names = risky.prefix(3).map(\.name).joined(separator: ", ")
            let extra = risky.count > 3 ? ", and \(risky.count - 3) more" : ""
            parts.append("Check these first: \(names)\(extra).")
        }
        let reasons = Set(risky.compactMap { risks[$0.path] })
        parts += TrashRisk.Reason.allCases.filter(reasons.contains).map(Self.explanation)
        parts.append("You can put items back from the Trash.")
        message = parts.joined(separator: " ")
    }

    private static func explanation(of reason: TrashRisk.Reason) -> String {
        switch reason {
        case .credentials: "Keys and passwords kept here sign you in to other services."
        case .iCloud: "Items in iCloud are also removed from your other devices."
        case .appData: "Apps keep settings and data here, and may stop working without them."
        case .topLevelFolder: "A folder at the top of your home goes with everything in it."
        case .outsideHome: "Items outside your home folder may be needed by other apps or accounts."
        }
    }
}
