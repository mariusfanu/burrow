import Foundation
import Testing
@testable import BurrowCore

@Suite struct TrashGuardTests {
    private func makeHome() throws -> String {
        let path = TestScratch.root + "burrow-guard-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path + "/Library/Mobile Documents/com~apple~CloudDocs/Documents/sub", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: path + "/Downloads/folder", withIntermediateDirectories: true)
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    @Test(arguments: [
        "/", "/Applications", "/Library", "/System", "/System/Library/Fonts", "/Users", "/usr/local/bin",
        "/Library/Keychains/x", "/private/var/db/x", "/var", "/private/var/folders", "/Volumes",
        "/opt/homebrew", "/bin/ls", "/Applications/Safari.app/Contents",
    ])
    func systemPathsAreRefused(path: String) {
        #expect(TrashGuard(home: "/nonexistent-home").isProtected(path))
    }

    @Test(arguments: ["", "relative/path", "/tmp/../etc/passwd", "/a/\0b"])
    func malformedPathsAreRefused(path: String) {
        #expect(throws: TrashGuard.Refusal.self) {
            try TrashGuard(home: "/nonexistent-home").validate(path)
        }
    }

    @Test func homeAndAnotherAccountAreRefused() throws {
        let home = try makeHome()
        let guardrail = TrashGuard(home: home)
        #expect(guardrail.isProtected(home))
        #expect(guardrail.isProtected("/Users/Shared"))
    }

    @Test func iCloudStructureIsProtectedButContentsAreNot() throws {
        let home = try makeHome()
        let guardrail = TrashGuard(home: home)
        let store = home + "/Library/Mobile Documents"
        #expect(guardrail.isProtected(store))
        #expect(guardrail.isProtected(store + "/com~apple~CloudDocs"))
        #expect(guardrail.isProtected(store + "/com~apple~CloudDocs/Documents"))
        #expect(!guardrail.isProtected(store + "/com~apple~CloudDocs/Documents/sub"))
        // An ancestor would carry the store along with it.
        #expect(guardrail.isProtected(home + "/Library"))
    }

    @Test func runtimeStateIsProtected() throws {
        let home = try makeHome()
        let guardrail = TrashGuard(home: home)
        #expect(guardrail.isProtected(home + "/.orbstack/data"))
        #expect(guardrail.isProtected(home + "/Library/Containers/com.docker.docker/Data"))
    }

    @Test func endpointSecurityCachesAreProtected() {
        let guardrail = TrashGuard(home: "/nonexistent-home")
        #expect(guardrail.isProtected("/private/var/folders/ab/cd/C"))
        #expect(guardrail.isProtected("/var/folders/ab/cd/C/com.crowdstrike.falcon/x"))
        #expect(!guardrail.isProtected("/private/var/folders/ab/cd/C/com.example.app"))
    }

    @Test func theRealHomeStaysProtectedWhenHOMEIsOverridden() {
        let guardrail = TrashGuard(home: "/nonexistent-home")
        #expect(guardrail.isProtected(NSHomeDirectory()))
    }

    @Test func ordinaryUserFilesAreAllowed() throws {
        let home = try makeHome()
        let guardrail = TrashGuard(home: home)
        #expect(throws: Never.self) { try guardrail.validate(home + "/Downloads/folder") }
    }

    @Test func symlinkIntoProtectedTreeIsRefused() throws {
        let home = try makeHome()
        let link = home + "/Downloads/sys"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/System/Library")
        #expect(throws: TrashGuard.Refusal.self) { try TrashGuard(home: home).validate(link) }
    }
}

@Suite struct OperationsLogTests {
    @Test func escapingMatchesTheShellContract() {
        #expect(OperationsLog.escape("a\nb\tc\u{1B}") == "a\\nb\\tc\\x1b")
        #expect(OperationsLog.escape(#"keep\back"#) == #"keep\back"#)
        #expect(OperationsLog.escape("名前.dmg") == "名前.dmg")
    }

    @Test func sizesMatchBytesToHuman() {
        #expect(OperationsLog.sizeText(Int64.min) == "0B")
        #expect(OperationsLog.sizeText(999) == "999B")
        #expect(OperationsLog.sizeText(1_500) == "2KB")
        #expect(OperationsLog.sizeText(999_999) == "1000KB")
        #expect(OperationsLog.sizeText(2_250_000) == "2.3MB")
        #expect(OperationsLog.sizeText(999_999_999) == "1000.0MB")
        #expect(OperationsLog.sizeText(1_930_000_000) == "1.93GB")
    }

    @Test func largeSizesKeepTheSharedDecimalRounding() {
        #expect(OperationsLog.sizeText(1_004_999_999) == "1.00GB")
        #expect(OperationsLog.sizeText(1_005_000_000) == "1.01GB")
        #expect(OperationsLog.sizeText(1_994_999_999) == "1.99GB")
        #expect(OperationsLog.sizeText(1_995_000_000) == "2.00GB")
        // The former multiply-then-round expression overflows just past this boundary.
        #expect(OperationsLog.sizeText(92_233_720_363_547_758) == "92233720.36GB")
        #expect(OperationsLog.sizeText(92_233_720_363_547_759) == "92233720.36GB")
        #expect(OperationsLog.sizeText(Int64.max) == "9223372036.85GB")
    }

    @Test func deletionSizesRoundUpWithoutOverflow() throws {
        let home = TestScratch.root + "burrow-log-" + UUID().uuidString
        let log = OperationsLog(home: home, command: "analyze", environment: [:])
        let cases: [(Int64, String)] = [
            (.min, "0"), (-1, "0"), (0, "0"), (1, "1"), (1024, "1"), (1025, "2"),
            (.max - 1023, "9007199254740991"),
            (.max - 1022, "9007199254740992"),
            (.max, "9007199254740992"),
        ]
        for (index, item) in cases.enumerated() {
            log.recordFailed(path: "/fixture/\(index)", size: item.0, reason: "fixture")
        }
        log.end(items: cases.count, bytes: .max)
        #expect(!log.writeFailed)

        let deletions = try String(contentsOfFile: home + "/Library/Logs/mole/deletions.log", encoding: .utf8)
        let rows = deletions.split(separator: "\n")
        try #require(rows.count == cases.count)
        for (row, item) in zip(rows, cases) {
            let fields = row.split(separator: "\t")
            try #require(fields.count == 5)
            #expect(fields[2] == item.1)
        }
    }

    @Test func rowsUseTheSharedFormat() throws {
        let home = TestScratch.root + "burrow-log-" + UUID().uuidString
        let log = OperationsLog(home: home, command: "analyze", environment: [:])
        log.begin()
        log.recordTrashed(path: "/tmp/x\ny", size: 2_000)
        log.recordFailed(path: "/System", size: 0, reason: "protected")
        log.end(items: 1, bytes: 2_000)

        let operations = try String(contentsOfFile: home + "/Library/Logs/mole/operations.log", encoding: .utf8)
        #expect(operations.contains("# ========== analyze run="))
        #expect(operations.contains("TRASHED /tmp/x\\ny (2KB)"))
        #expect(operations.contains("FAILED /System (protected)"))
        #expect(operations.contains("session ended at"))
        #expect(operations.contains("1 items, 2KB =========="))

        let deletions = try String(contentsOfFile: home + "/Library/Logs/mole/deletions.log", encoding: .utf8)
        let row = try #require(deletions.split(separator: "\n").first).split(separator: "\t")
        #expect(row.count == 5)
        #expect(row[1] == "trash")
        #expect(row[2] == "2")
        #expect(row[3] == "ok")
    }

    @Test func theOptOutSilencesOperationsButNotDeletions() {
        let home = TestScratch.root + "burrow-log-" + UUID().uuidString
        let log = OperationsLog(home: home, command: "analyze", environment: ["MO_NO_OPLOG": "1"])
        log.begin()
        log.recordTrashed(path: "/tmp/x", size: 1)
        #expect(!FileManager.default.fileExists(atPath: home + "/Library/Logs/mole/operations.log"))
        #expect(FileManager.default.fileExists(atPath: home + "/Library/Logs/mole/deletions.log"))
    }

    @Test(.hostIntegration) func trashedItemsCanBePutBack() async throws {
        let home = "/tmp/burrow-test-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: home) }
        try FileManager.default.createDirectory(atPath: home + "/Downloads", withIntermediateDirectories: true)
        let path = home + "/Downloads/burrowtest-undo-\(UUID().uuidString.prefix(6)).bin"
        try Data([1, 2, 3]).write(to: URL(fileURLWithPath: path))

        let report = await TrashMover.trash(entries: [(path: path, size: 3)], guardrail: TrashGuard(home: home), home: home, environment: [:])
        let trashed = try #require(report.outcomes.first?.trashedItem)
        #expect(trashed.identity != nil)
        #expect(!FileManager.default.fileExists(atPath: path))

        let restored = TrashMover.restore([trashed], home: home, environment: [:])
        #expect(restored.outcomes.first?.error == nil)
        #expect(FileManager.default.fileExists(atPath: path))
        let log = try String(contentsOfFile: home + "/Library/Logs/mole/operations.log", encoding: .utf8)
        #expect(log.contains("TRASHED"))
        #expect(log.contains("RESTORED"))
    }

    @Test func undoLeavesADifferentItemThatTookTheSameName() throws {
        let home = TestScratch.root + "burrow-undo-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        let original = home + "/report.pdf"
        let stored = home + "/stored-report.pdf"
        try Data([1]).write(to: URL(fileURLWithPath: stored))
        let identity = try #require(TrashMover.FileIdentity(path: stored))
        // The Trash is emptied, and then another file with this name lands there.
        let other = home + "/other.pdf"
        try Data([2]).write(to: URL(fileURLWithPath: other))
        #expect(rename(other, stored) == 0)

        let item = TrashMover.TrashedItem(trashedURL: URL(fileURLWithPath: stored), originalPath: original, identity: identity)
        let report = TrashMover.restore([item], home: home, environment: [:])
        #expect(report.outcomes.first?.error?.contains("isn’t the one Burrow moved") == true)
        #expect(!FileManager.default.fileExists(atPath: original))
        #expect(try Data(contentsOf: URL(fileURLWithPath: stored)) == Data([2]))
    }

    @Test func undoNeverOverwritesANewFile() throws {
        let home = TestScratch.root + "burrow-undo-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        let original = home + "/file.bin"
        let stored = home + "/stored.bin"
        try Data([1]).write(to: URL(fileURLWithPath: stored))
        try Data([2]).write(to: URL(fileURLWithPath: original))

        let identity = try #require(TrashMover.FileIdentity(path: stored))
        let item = TrashMover.TrashedItem(trashedURL: URL(fileURLWithPath: stored), originalPath: original, identity: identity)
        let report = TrashMover.restore([item], home: home, environment: [:])
        #expect(report.outcomes.first?.error != nil)
        #expect(try Data(contentsOf: URL(fileURLWithPath: original)) == Data([2]))
        #expect(FileManager.default.fileExists(atPath: stored))
    }

    @Test func undoRefusesAnItemWithoutARecordedIdentity() throws {
        let home = TestScratch.root + "burrow-undo-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        let original = home + "/file.bin"
        let stored = URL(fileURLWithPath: home + "/stored.bin")
        try Data([1]).write(to: stored)

        let item = TrashMover.TrashedItem(trashedURL: stored, originalPath: original)
        let report = TrashMover.restore([item], home: home, environment: [:])
        #expect(report.outcomes.first?.error != nil)
        #expect(!FileManager.default.fileExists(atPath: original))
        #expect(FileManager.default.fileExists(atPath: stored.path))
    }

    @Test func alreadyMissingPathsAreNotLogged() async throws {
        let home = TestScratch.root + "burrow-log-" + UUID().uuidString
        let missing = home + "/Downloads/gone.bin"
        let report = await TrashMover.trash(
            entries: [(path: missing, size: 10)],
            guardrail: TrashGuard(home: home),
            home: home,
            environment: [:]
        )
        #expect(report.outcomes.first?.error == nil)
        let log = try String(contentsOfFile: home + "/Library/Logs/mole/operations.log", encoding: .utf8)
        #expect(report.outcomes.first?.status == .alreadyMissing)
        #expect(!log.contains("gone.bin"))
    }
}

@Suite struct ConfigTests {
    @Test(arguments: [false, true]) func savingPreservesAValidFinalSymlink(relative: Bool) throws {
        let home = TestScratch.root + "burrow-link-" + UUID().uuidString
        let directory = home + "/.config/mole"
        let target = directory + "/linked-whitelist"
        let link = directory + "/whitelist"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try "/tmp/keep\n".write(toFile: target, atomically: true, encoding: .utf8)
        let destination = relative ? "linked-whitelist" : target
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: destination)
        try WhitelistStore(home: home, cliRoot: nil).add("/tmp/new")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link) == destination)
        #expect(try String(contentsOfFile: target, encoding: .utf8).contains("/tmp/new"))
    }

    @Test func aPurgeDraftCannotOverwriteAChangedFile() throws {
        let store = PurgePathsStore(home: TestScratch.root + UUID().uuidString)
        try store.save(["~/old"])
        let original = try store.snapshot()
        try store.save(["~/external"])
        #expect(throws: ConfigError.changed("purge_paths")) { try store.save(["~/draft"], replacing: original) }
        #expect(try store.load() == ["~/external"])
    }

    private let baseScript = #"""
    declare -a DEFAULT_WHITELIST_PATTERNS=(
        "$HOME/Library/Caches/ms-playwright*"
        "$HOME/.ollama/models/*"
        "$FINDER_METADATA_SENTINEL"
    )

    declare -a DEFAULT_OPTIMIZE_WHITELIST_PATTERNS=(
    )
    """#

    @Test func defaultsParseFromTheCLI() {
        let defaults = WhitelistStore.parseDefaults(fromBaseScript: baseScript, home: "/Users/a")
        #expect(defaults == ["/Users/a/Library/Caches/ms-playwright*", "/Users/a/.ollama/models/*", "FINDER_METADATA"])
    }

    @Test func firstSaveKeepsDefaultsBecauseAFileReplacesThem() throws {
        let root = TestScratch.root + "burrow-wl-" + UUID().uuidString
        let cli = root + "/cli/lib/core"
        try FileManager.default.createDirectory(atPath: cli, withIntermediateDirectories: true)
        try baseScript.write(toFile: cli + "/base.sh", atomically: true, encoding: .utf8)

        let store = WhitelistStore(home: root, cliRoot: root + "/cli")
        #expect(store.usesDefaults)
        #expect(try store.load().count == 3)

        try store.add("/Users/a/keep")
        #expect(!store.usesDefaults)
        let saved = try store.load()
        #expect(saved.contains("/Users/a/keep"))
        #expect(saved.contains("FINDER_METADATA"))
        #expect(saved.count == 4)

        try store.add("/Users/a/keep")
        #expect(try store.load().count == 4)
        try store.remove("/Users/a/keep")
        #expect(try store.load().count == 3)
    }

    private func makeConfigHome() throws -> String {
        let home = TestScratch.root + "burrow-cfg-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home + "/.config/mole", withIntermediateDirectories: true)
        return home
    }

    @Test func unreadableWhitelistIsNeverOverwritten() throws {
        let home = try makeConfigHome()
        let path = home + "/.config/mole/whitelist"
        let original = Data([0x2F, 0x61, 0xFF, 0xFE, 0x0A])
        try original.write(to: URL(fileURLWithPath: path))

        let store = WhitelistStore(home: home, cliRoot: nil)
        #expect(throws: ConfigError.self) { try store.load() }
        #expect(throws: ConfigError.self) { try store.add("/Users/a/keep") }
        #expect(throws: ConfigError.self) { try store.save(["/Users/a/keep"]) }
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == original)
    }

    @Test func aDanglingWhitelistCannotFallBackOrReplaceItsLink() throws {
        let home = try makeConfigHome()
        let cli = home + "/cli/lib/core"
        try FileManager.default.createDirectory(atPath: cli, withIntermediateDirectories: true)
        try baseScript.write(toFile: cli + "/base.sh", atomically: true, encoding: .utf8)
        let path = home + "/.config/mole/whitelist"
        let target = home + "/missing-whitelist"
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)

        let store = WhitelistStore(home: home, cliRoot: home + "/cli")
        #expect(throws: ConfigError.self) { try store.load() }
        #expect(throws: ConfigError.self) { try store.add("/Users/a/keep") }
        #expect(throws: ConfigError.self) { try store.save(["/Users/a/keep"]) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: path) == target)
        #expect(!FileManager.default.fileExists(atPath: target))
    }

    @Test func aDanglingOptimizeWhitelistDoesNotAuthorizeLegacyFallback() throws {
        let home = try makeConfigHome()
        try "cache_refresh\n".write(toFile: home + "/.config/mole/whitelist_checks", atomically: true, encoding: .utf8)
        let path = home + "/.config/mole/whitelist_optimize"
        let target = home + "/missing-exclusions"
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)

        let store = OptimizeWhitelistStore(home: home, cliRoot: nil)
        #expect(throws: ConfigError.self) { try store.load() }
        #expect(throws: ConfigError.self) { try store.save(["sqlite_vacuum"]) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: path) == target)
        #expect(try String(contentsOfFile: home + "/.config/mole/whitelist_checks", encoding: .utf8) == "cache_refresh\n")
    }

    @Test func aDanglingParentIsNotAnAbsentPurgeConfiguration() throws {
        let home = try makeConfigHome()
        let directory = home + "/.config/mole"
        let target = home + "/missing-directory"
        try FileManager.default.removeItem(atPath: directory)
        try FileManager.default.createSymbolicLink(atPath: directory, withDestinationPath: target)

        let store = PurgePathsStore(home: home)
        #expect(throws: ConfigError.self) { try store.load() }
        #expect(throws: ConfigError.self) { try store.save(["~/Developer"]) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: directory) == target)
        #expect(!FileManager.default.fileExists(atPath: target))
    }

    @Test func anAbsentFileInsideALinkedDirectoryCanStillBeCreated() throws {
        let home = try makeConfigHome()
        let directory = home + "/.config/mole"
        let target = home + "/configuration"
        try FileManager.default.moveItem(atPath: directory, toPath: target)
        try FileManager.default.createSymbolicLink(atPath: directory, withDestinationPath: target)

        let store = PurgePathsStore(home: home)
        #expect(try store.load().isEmpty)
        try store.save(["~/Developer"])
        #expect(try store.load() == ["~/Developer"])
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: directory) == target)
        #expect(FileManager.default.fileExists(atPath: target + "/purge_paths"))
    }

    @Test func crlfWhitelistKeepsItsEntries() throws {
        let home = try makeConfigHome()
        try "# comment\r\n/Users/a/one\r\n/Users/a/two\r\n".write(
            toFile: home + "/.config/mole/whitelist", atomically: true, encoding: .utf8
        )
        #expect(try WhitelistStore(home: home, cliRoot: nil).load() == ["/Users/a/one", "/Users/a/two"])
    }

    @Test func firstSaveRefusedWhenDefaultsAreUnknown() throws {
        let store = WhitelistStore(home: try makeConfigHome(), cliRoot: nil)
        #expect(throws: ConfigError.defaultsUnavailable) { try store.add("/Users/a/keep") }
        #expect(store.usesDefaults)
    }

    @Test(arguments: ["~/app..old", "relative/path", "/a//b", "/System/x", "/usr/bin/x", "/", "/a\tb"])
    func patternsTheCLIWouldIgnoreAreRefused(pattern: String) {
        #expect(WhitelistStore.problem(with: pattern, home: "/Users/a") != nil)
    }

    @Test(arguments: ["~/Library/Caches/x*", "$HOME/keep", "/Users/a/keep", "FINDER_METADATA"])
    func validPatternsAreAccepted(pattern: String) {
        #expect(WhitelistStore.problem(with: pattern, home: "/Users/a") == nil)
    }

    @Test func legacyOptimizeExclusionsCarryOver() throws {
        let home = try makeConfigHome()
        try "cache_refresh\n".write(toFile: home + "/.config/mole/whitelist_checks", atomically: true, encoding: .utf8)
        let store = OptimizeWhitelistStore(home: home, cliRoot: nil)
        #expect(try store.load() == ["cache_refresh"])

        try store.save(try store.load().union(["sqlite_vacuum"]))
        #expect(try store.load() == ["cache_refresh", "sqlite_vacuum"])
    }

    @Test func unreadablePurgePathsThrow() throws {
        let home = try makeConfigHome()
        try Data([0xFF, 0xFE]).write(to: URL(fileURLWithPath: home + "/.config/mole/purge_paths"))
        #expect(throws: ConfigError.self) { try PurgePathsStore(home: home).load() }
    }

    @Test func purgePathsRoundTrip() throws {
        let store = PurgePathsStore(home: TestScratch.root + "burrow-pp-" + UUID().uuidString)
        #expect(try store.load().isEmpty)
        try store.save(["~/Developer", "/Volumes/Work"])
        #expect(try store.load() == ["~/Developer", "/Volumes/Work"])
    }

    @Test func optimizeTasksParseFromCatalog() {
        let source = #"""
        _optimize_catalog_register cache_refresh opt_cache_refresh \
            "Finder Cache Refresh" "Finder Refresh" \
            "Refresh QuickLook" true
        _optimize_catalog_register sqlite_vacuum opt_sqlite_vacuum \
            "Database Optimization" "Database Optimization" \
            "Compress" true
        """#
        let tasks = OptimizeWhitelistStore.parseTasks(source)
        #expect(tasks.map(\.action) == ["cache_refresh", "sqlite_vacuum"])
        #expect(tasks.first?.name == "Finder Refresh")
    }
}

@Suite struct TrashRiskTests {
    private let risk = TrashRisk(home: "/Users/me")

    @Test(arguments: [
        ("/Users/me/.ssh", true, TrashRisk.Reason.credentials),
        ("/Users/me/.ssh/id_ed25519", false, .credentials),
        ("/Users/me/.aws/credentials", false, .credentials),
        ("/Users/me/Library/Keychains", true, .credentials),
        ("/Users/me/Library/Keychains/login.keychain-db", false, .credentials),
        ("/Users/me/Library/Mobile Documents/com~apple~CloudDocs/x.pdf", false, .iCloud),
        ("/Users/me/.config", true, .appData),
        ("/Users/me/.config/mole/whitelist", false, .appData),
        ("/Users/me/.zshrc", false, .appData),
        ("/Users/me/Library/Application Support", true, .appData),
        ("/Users/me/Library/Preferences/com.example.plist", false, .appData),
        ("/Users/me/Documents", true, .topLevelFolder),
        ("/Users/me/Desktop/", true, .topLevelFolder),
        ("/USERS/ME/DOCUMENTS", true, .topLevelFolder),
        ("/Applications/Utilities", true, .outsideHome),
        ("/Applications/Utilities/Terminal.app", true, .outsideHome),
        ("/Library/LaunchDaemons", true, .outsideHome),
        ("/opt/homebrew/bin", true, .outsideHome),
        ("/Users/Shared/data", true, .outsideHome),
        ("/Volumes/Backup", true, .outsideHome),
    ])
    func flagged(path: String, isDirectory: Bool, reason: TrashRisk.Reason) {
        #expect(risk.reason(forPath: path, isDirectory: isDirectory) == reason)
    }

    @Test(arguments: [
        ("/Users/me/Downloads/big.iso", false),
        ("/Users/me/Downloads/old-project", true),
        ("/Users/me/Documents/notes.txt", false),
        ("/Users/me/big.iso", false),
        ("/Users/me/Library/Caches/com.example/data", true),
        ("/Users/me/Library/Application Support/Example", true),
        ("/Applications/Example.app", true),
        ("/Volumes/Backup/old.dmg", false),
        ("/tmp/scratch", true),
        ("/private/var/folders/ab/cd/T/x", true),
    ])
    func ordinary(path: String, isDirectory: Bool) {
        #expect(risk.reason(forPath: path, isDirectory: isDirectory) == nil)
    }

    @Test func aLinkedParentCantHideASensitivePlace() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
            .appendingPathComponent("burrow-risk-" + UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let home = root + "/home"
        try FileManager.default.createDirectory(atPath: home + "/.ssh", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: home + "/Downloads", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: home + "/Downloads/keys", withDestinationPath: home + "/.ssh")
        let risk = TrashRisk(home: home)
        #expect(risk.reason(forPath: home + "/Downloads/keys/id_ed25519", isDirectory: false) == .credentials)
        // Moving the link itself leaves its target alone.
        #expect(risk.reason(forPath: home + "/Downloads/keys", isDirectory: false) == nil)
    }
}
