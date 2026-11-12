import BurrowCore
import Foundation

/// A set of items moved to the Trash, kept so that Undo can put them back.
struct TrashedBatch: Sendable {
    let id = UUID()
    let items: [TrashMover.TrashedItem]
}
