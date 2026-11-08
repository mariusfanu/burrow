import Testing
@testable import Burrow

@MainActor
struct ExecutionPolicyTests {
    @Test func forcedPreviewCannotBeDisabled() {
        let policy = ExecutionPolicy(defaults: nil, forced: true)
        policy.previewMode = false
        #expect(policy.effectivePreview)
    }
}
