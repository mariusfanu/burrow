import Foundation
import Testing
@testable import Burrow

@MainActor
struct ExecutionPolicyTests {
    @Test func forcedPreviewCannotBeDisabled() {
        let policy = ExecutionPolicy(defaults: nil, forced: true)
        policy.previewMode = false
        #expect(policy.effectivePreview)
    }

    @Test func unforcedDefaultsToFalseAndPersistsChangesInUserDefaults() throws {
        let suite = "ExecutionPolicyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = ExecutionPolicy(defaults: defaults, forced: false)
        #expect(!initial.isPreviewForced)
        #expect(!initial.previewMode)
        #expect(!initial.effectivePreview)

        initial.previewMode = true
        #expect(defaults.bool(forKey: "previewMode"))

        let reloaded = ExecutionPolicy(defaults: defaults, forced: false)
        #expect(reloaded.previewMode)
        #expect(reloaded.effectivePreview)

        reloaded.previewMode = false
        #expect(!defaults.bool(forKey: "previewMode"))
    }
}
