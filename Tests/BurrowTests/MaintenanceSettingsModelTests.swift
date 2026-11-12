import Foundation
import Testing
import BurrowCore
@testable import Burrow

@MainActor
struct MaintenanceSettingsModelTests {
    @Test func failedSaveKeepsTheTaskEnabledAndSuccessfulRetryClearsTheError() {
        let model = MaintenanceSettingsModel()
        model.load(tasks: [], read: { ["existing-exclusion"] })
        model.setEnabled(false, action: "maintenance") { _, _ in throw CocoaError(.fileWriteNoPermission) }
        #expect(model.isEnabled("maintenance"))
        #expect(model.errorMessage != nil)
        var persisted: Set<String> = []
        model.setEnabled(false, action: "maintenance") { enabled, action in
            #expect(!enabled)
            persisted = ["existing-exclusion", action]
            return persisted
        }
        #expect(persisted == ["existing-exclusion", "maintenance"])
        #expect(!model.isEnabled("maintenance"))
        #expect(model.errorMessage == nil)
    }

    @Test func unreadableConfigurationCannotBeReplacedByAToggle() {
        let model = MaintenanceSettingsModel()
        model.load(tasks: [], read: { throw CocoaError(.fileReadNoPermission) })
        var writes = 0
        model.setEnabled(false, action: "maintenance") { _, _ in
            writes += 1
            return []
        }
        #expect(writes == 0)
        #expect(!model.isLoaded)
    }

    @Test func aTogglePreservesAnEditMadeAfterThePaneLoaded() throws {
        let home = TestScratch.root + UUID().uuidString
        let store = OptimizeWhitelistStore(home: home, cliRoot: nil)
        try store.save(["original"])
        let model = MaintenanceSettingsModel()
        model.load(tasks: [], read: store.load)
        try store.save(["original", "external"])
        model.setEnabled(false, action: "chosen", save: store.setEnabled)
        #expect(try store.load() == ["original", "external", "chosen"])
        #expect(model.excluded == ["original", "external", "chosen"])
    }
}
