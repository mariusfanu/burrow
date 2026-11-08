import Foundation
import Testing
@testable import Burrow

@MainActor
struct MaintenanceSettingsModelTests {
    @Test func failedSaveKeepsTheTaskEnabledAndSuccessfulRetryClearsTheError() {
        let model = MaintenanceSettingsModel()
        model.load(tasks: [], read: { ["existing-exclusion"] })
        model.setEnabled(false, action: "maintenance") { _ in throw CocoaError(.fileWriteNoPermission) }
        #expect(model.isEnabled("maintenance"))
        #expect(model.errorMessage != nil)
        var persisted: Set<String> = []
        model.setEnabled(false, action: "maintenance") { persisted = $0 }
        #expect(persisted == ["existing-exclusion", "maintenance"])
        #expect(!model.isEnabled("maintenance"))
        #expect(model.errorMessage == nil)
    }

    @Test func unreadableConfigurationCannotBeReplacedByAToggle() {
        let model = MaintenanceSettingsModel()
        model.load(tasks: [], read: { throw CocoaError(.fileReadNoPermission) })
        var writes = 0
        model.setEnabled(false, action: "maintenance") { _ in writes += 1 }
        #expect(writes == 0)
        #expect(!model.isLoaded)
    }
}
