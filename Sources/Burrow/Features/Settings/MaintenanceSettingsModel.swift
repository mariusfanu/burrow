import BurrowCore
import Foundation
import Observation

@MainActor
@Observable
final class MaintenanceSettingsModel {
    private(set) var excluded: Set<String> = []
    private(set) var tasks: [OptimizeWhitelistStore.Task] = []
    private(set) var isLoaded = false
    private(set) var errorMessage: String?

    func load(tasks: [OptimizeWhitelistStore.Task], read: () throws -> Set<String>) {
        self.tasks = tasks
        do {
            excluded = try read()
            errorMessage = nil
            isLoaded = true
        } catch {
            isLoaded = false
            errorMessage = error.localizedDescription
        }
    }

    func isEnabled(_ action: String) -> Bool { !excluded.contains(action) }

    func setEnabled(_ enabled: Bool, action: String, save: (Set<String>) throws -> Void) {
        guard isLoaded else { return }
        var proposed = excluded
        if enabled { proposed.remove(action) }
        else { proposed.insert(action) }
        do {
            try save(proposed)
            excluded = proposed
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
