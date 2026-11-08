import Foundation
import Testing
@testable import Burrow

@MainActor
struct CleanProtectionTests {
    @Test(arguments: [false, true])
    func aCapturedProtectionActionRechecksLiveAndForcedPreview(forced: Bool) throws {
        let home = TestScratch.root + "burrow-clean-protection-" + UUID().uuidString
        let directory = URL(fileURLWithPath: home + "/.config/mole")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let whitelist = directory.appendingPathComponent("whitelist")
        let original = Data("# Keep the existing configuration verbatim\n/Users/fixture/existing\n".utf8)
        try original.write(to: whitelist)
        defer { try? FileManager.default.removeItem(atPath: home) }

        let policy = ExecutionPolicy(defaults: nil, forced: forced)
        let model = CleanModel(policy: policy, home: home)
        let path = "/Users/fixture/keep"
        let protect = { model.protect(path: path, cli: fixtureCLI) }
        let previousSession = model.protectedThisSession
        // The action can outlive the editable UI; forced Preview also ignores this setter.
        policy.previewMode = !forced
        #expect(policy.effectivePreview)
        protect()

        #expect(try Data(contentsOf: whitelist) == original)
        #expect(model.protectedThisSession == previousSession)
        #expect(model.errorMessage == nil)

        if !forced {
            policy.previewMode = false
            protect()
            let saved = try String(contentsOf: whitelist, encoding: .utf8)
            #expect(saved.contains("/Users/fixture/existing"))
            #expect(saved.contains(path))
            #expect(model.protectedThisSession == [path])
            #expect(model.errorMessage == nil)
        }
    }
}
