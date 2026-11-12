import BurrowCore

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
