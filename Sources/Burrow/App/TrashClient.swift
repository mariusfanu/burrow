import BurrowCore
import Foundation

struct TrashClient: Sendable {
    var trash: @Sendable ([(path: String, size: Int64)], String) async -> TrashMover.Report = { entries, home in
        await TrashMover.trash(entries: entries, guardrail: TrashGuard(home: home), home: home)
    }
    var restore: @Sendable ([TrashMover.TrashedItem], String) async -> TrashMover.Report = { items, home in
        await Task.detached { TrashMover.restore(items, home: home) }.value
    }
}
