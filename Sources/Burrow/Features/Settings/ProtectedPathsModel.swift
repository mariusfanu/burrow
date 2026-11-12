import BurrowCore
import Foundation
import Observation

/// The Protected pane's list. Edits are refused in Preview Mode at the moment they run, not
/// when the control was drawn, because a file chooser can return after the mode has changed.
@MainActor
@Observable
final class ProtectedPathsModel {
    private(set) var patterns: [String] = []
    private(set) var usesDefaults = false
    private(set) var isLoaded = false
    var errorMessage: String?

    func load(from store: WhitelistStore) {
        usesDefaults = store.usesDefaults
        do {
            patterns = try store.load()
            isLoaded = true
        } catch {
            isLoaded = false
            errorMessage = error.localizedDescription
        }
    }

    /// Adds what was typed in the field, trimmed and with a leading `~/` expanded.
    /// Returns whether it was saved, so the field can keep text that wasn't.
    func addTyped(_ text: String, to store: WhitelistStore, home: String, isPreview: Bool) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let expanded = trimmed.hasPrefix("~/") ? home + trimmed.dropFirst(1) : trimmed
        return add(expanded, to: store, isPreview: isPreview)
    }

    /// Adds a pattern exactly as given, such as a folder from the chooser.
    @discardableResult
    func add(_ pattern: String, to store: WhitelistStore, isPreview: Bool) -> Bool {
        guard isLoaded, !isPreview else { return false }
        do {
            try store.add(pattern)
            errorMessage = nil
            load(from: store)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Returns whether the pattern was removed, so the selection can be cleared only then.
    @discardableResult
    func remove(_ pattern: String, from store: WhitelistStore, isPreview: Bool) -> Bool {
        guard isLoaded, !isPreview else { return false }
        do {
            try store.remove(pattern)
            load(from: store)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
