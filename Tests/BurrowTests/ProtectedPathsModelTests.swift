import BurrowCore
import Foundation
import Testing
@testable import Burrow

@MainActor
struct ProtectedPathsModelTests {
    private struct Fixture {
        let home = TestScratch.root + "protected-" + UUID().uuidString
        var whitelist: String { home + "/.config/mole/whitelist" }
        var defaultPattern: String { home + "/Library/Caches/example*" }
        var store: WhitelistStore { WhitelistStore(home: home, cliRoot: home + "/cli") }

        init() throws {
            let core = home + "/cli/lib/core"
            try FileManager.default.createDirectory(atPath: core, withIntermediateDirectories: true)
            try #"""
            declare -a DEFAULT_WHITELIST_PATTERNS=(
                "$HOME/Library/Caches/example*"
            )
            """#.write(toFile: core + "/base.sh", atomically: true, encoding: .utf8)
        }
    }

    @Test func missingWhitelistShowsDefaults() throws {
        let fixture = try Fixture()
        let model = ProtectedPathsModel()
        model.load(from: fixture.store)
        #expect(model.isLoaded)
        #expect(model.usesDefaults)
        #expect(model.patterns == [fixture.defaultPattern])
    }

    @Test func firstAddPreservesDefaultsAndReloadsFromDisk() throws {
        let fixture = try Fixture()
        let model = ProtectedPathsModel()
        model.load(from: fixture.store)
        let path = fixture.home + "/Keep"
        #expect(model.add(path, to: fixture.store, isPreview: false))
        #expect(!model.usesDefaults)
        #expect(model.patterns == [fixture.defaultPattern, path])
        #expect(try fixture.store.load() == model.patterns)
    }

    @Test func typedPathsAreTrimmedAndExpandedAndBlankInputIsIgnored() throws {
        let fixture = try Fixture()
        let model = ProtectedPathsModel()
        model.load(from: fixture.store)
        #expect(!model.addTyped("   ", to: fixture.store, home: fixture.home, isPreview: false))
        #expect(fixture.store.usesDefaults)
        #expect(model.addTyped("  ~/Projects/keep ", to: fixture.store, home: fixture.home, isPreview: false))
        #expect(try fixture.store.load() == [fixture.defaultPattern, fixture.home + "/Projects/keep"])
    }

    @Test func anInvalidPatternReportsAnErrorWithoutWriting() throws {
        let fixture = try Fixture()
        let model = ProtectedPathsModel()
        model.load(from: fixture.store)
        #expect(!model.addTyped("../x", to: fixture.store, home: fixture.home, isPreview: false))
        #expect(model.errorMessage != nil)
        #expect(fixture.store.usesDefaults)
    }

    @Test func previewRejectsEveryEditWithoutWriting() throws {
        let fixture = try Fixture()
        let model = ProtectedPathsModel()
        model.load(from: fixture.store)
        #expect(!model.add(fixture.home + "/Keep", to: fixture.store, isPreview: true))
        #expect(!model.addTyped("~/Keep", to: fixture.store, home: fixture.home, isPreview: true))
        #expect(!model.remove(fixture.defaultPattern, from: fixture.store, isPreview: true))
        #expect(fixture.store.usesDefaults)
        #expect(model.patterns == [fixture.defaultPattern])
    }

    @Test func unreadableWhitelistDisablesEditsAndPreservesTheFile() throws {
        let fixture = try Fixture()
        let url = URL(fileURLWithPath: fixture.whitelist)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let invalid = Data([0xFF])
        try invalid.write(to: url)
        let model = ProtectedPathsModel()
        model.load(from: fixture.store)
        #expect(!model.isLoaded)
        #expect(model.errorMessage != nil)
        #expect(!model.add(fixture.home + "/Keep", to: fixture.store, isPreview: false))
        #expect(!model.remove(fixture.defaultPattern, from: fixture.store, isPreview: false))
        #expect(try Data(contentsOf: url) == invalid)
    }

    @Test func removeDeletesOnlyTheSelectedPattern() throws {
        let fixture = try Fixture()
        let remove = fixture.home + "/Keep"
        let similar = remove + " Also"
        try fixture.store.save([fixture.defaultPattern, remove, similar])
        let model = ProtectedPathsModel()
        model.load(from: fixture.store)
        #expect(model.remove(remove, from: fixture.store, isPreview: false))
        #expect(model.patterns == [fixture.defaultPattern, similar])
        #expect(try fixture.store.load() == model.patterns)
    }
}
