import Foundation

/// A distinct Undo target lets the toast consume just its own registration.
@MainActor
final class TrashUndoAction {
    let restore: @MainActor () -> Void

    init(restore: @escaping @MainActor () -> Void) {
        self.restore = restore
    }
}
