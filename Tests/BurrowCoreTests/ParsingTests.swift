import Foundation
import Testing
@testable import BurrowCore

@Suite struct ParsingTests {
    @Test func sizeTextReadsDecimalUnits() {
        #expect(SizeText.bytes(from: "93.6MB") == 93_600_000)
        #expect(SizeText.bytes(from: "15+ dirs, 7.07GB+") == 7_070_000_000)
        #expect(SizeText.bytes(from: "786KB") == 786_000)
        #expect(SizeText.bytes(from: "nothing") == nil)
    }

    @Test func logLineClassifiesByIcon() {
        let row = LogLine(id: 0, raw: "  ○ User app cache · 4 items, 93.6MB dry")
        #expect(row.kind == .preview)
        #expect(row.title == "User app cache")
        #expect(row.detail == "4 items, 93.6MB")
        #expect(row.bytes == 93_600_000)
        #expect(row.isIndented)

        #expect(LogLine(id: 1, raw: "➤ App caches").kind == .section)
        #expect(LogLine(id: 2, raw: "  ✓ Nothing to clean").kind == .success)
        #expect(LogLine(id: 3, raw: "  ◎ Trash · skipped, grant Full Disk Access").kind == .note)
        #expect(LogLine(id: 4, raw: "☻ broken").kind == .failure)
        #expect(LogLine.isDecoration("======"))
        #expect(!LogLine.isDecoration("Potential space"))
    }

    @Test func cleanReportParsesSectionsSummaryAndPaths() {
        let output = """
        \u{1B}[1;35mClean Your Mac\u{1B}[0m

        \u{1B}[0;38;5;244m◎ System caches need sudo\u{1B}[0m
        \u{1B}[1;34m⚙\u{1B}[0m Whitelist: 22 core patterns active

        \u{1B}[1;35m➤ User essentials\u{1B}[0m
          \u{1B}[0;33m○\u{1B}[0m User app cache\u{1B}[0m · 4 items, \u{1B}[0;33m93.6MB\u{1B}[0m \u{1B}[0;33mdry\u{1B}[0m
          \u{1B}[0;38;5;244m◎\u{1B}[0m Trash · skipped, grant Full Disk Access to your terminal

        \u{1B}[1;35m➤ Cloud & Office\u{1B}[0m
          \u{1B}[0;32m✓\u{1B}[0m Nothing to clean

        ======================================================================
        Dry run complete - no changes made
        Potential space: \u{1B}[0;31m1.93GB\u{1B}[0m · 85 items
        Detailed file list: /tmp/clean-list.txt
        ======================================================================
        """
        let list = """
        # Mole Cleanup Preview
        === User essentials ===
        /Users/a/Library/Caches/small  # 1KB
        /Users/a/Library/Caches/big  # 52.9MB
        """
        let report = CleanReport.parse(preview: output, pathList: list)
        #expect(report.sections.map(\.name) == ["User essentials", "Cloud & Office"])
        #expect(report.potentialText == "1.93GB")
        #expect(report.itemCount == 85)
        #expect(report.potentialBytes == 1_930_000_000)
        #expect(report.sections[0].bytes == 93_600_000)
        #expect(report.sections[0].paths.first?.path == "/Users/a/Library/Caches/big")
        #expect(report.sections[1].isEmpty)
        #expect(!report.sections[0].isEmpty)
        #expect(report.notes.contains { $0.contains("Whitelist") })
    }

    @Test func promptDetectorRecognizesOnlyRealPrompts() {
        #expect(PromptDetector.detect(partial: "➤ System caches need sudo. Enter continue, Space skip:") == .systemCleanChoice)
        #expect(PromptDetector.detect(partial: "Password:") == .password("Password:"))
        #expect(PromptDetector.detect(partial: "[sudo] password for marius:") == .password("[sudo] password for marius:"))
        #expect(PromptDetector.detect(partial: "Your password: is required soon") == nil)
        // Progress lines can quote any path, so a match must be the whole line.
        #expect(PromptDetector.detect(partial: "Scanning projects · ~/password:") == nil)
        #expect(PromptDetector.detect(partial: "⠴ Scanning ~/notes [y/N]") == nil)
        #expect(PromptDetector.detect(partial: "Checking ~/Enter to confirm, ESC cancel/file") == nil)
        #expect(PromptDetector.detect(partial: "➤ Remove 1 app, 682.6MB  Enter confirm, ESC cancel:")
            == .confirm("Remove 1 app, 682.6MB  Enter confirm, ESC cancel:"))
        #expect(PromptDetector.detect(partial: "◎ Press Enter to enable, Q to quit:")
            == .confirm("Press Enter to enable, Q to quit:"))
        #expect(PromptDetector.detect(partial: "➤ Enable completion for zsh? Enter confirm / Q cancel:") != nil)
        #expect(PromptDetector.detect(partial: "Continue anyway? [y/N]") == .yesNo("Continue anyway? [y/N]"))
        #expect(PromptDetector.detect(partial: "Scanning files...") == nil)
        #expect(PromptDetector.detect(partial: "Enter your credentials:") == nil)
    }

    @Test func menuParserReadsInstallerMenu() throws {
        let lines = [
            "Select Installers to Remove , 0B, 0 selected",
            "",
            "➤ ○ Antigravity.dmg                           212.8MB | Downloads",
            "  ● OpenUsage-0.7.6.dmg                        19.0MB | Downloads",
            "",
            "↑↓  |  Space Select  |  Enter Confirm  |  A All  |  I Invert  |  Q Quit",
        ]
        let menu = try #require(MenuParser.parse(lines: lines))
        #expect(menu.rows.count == 2)
        #expect(menu.cursor?.text.hasPrefix("Antigravity.dmg") == true)
        #expect(menu.reportedSelectedCount == 0)
        #expect(menu.position == nil)

        let item = MenuItem.parse(row: menu.rows[0], index: 0)
        #expect(item.name == "Antigravity.dmg")
        #expect(item.sizeText == "212.8MB")
        #expect(item.tag == "Downloads")
    }

    @Test func menuParserReadsPurgeRowsAndFocusedPath() throws {
        let lines = [
            "Select Artifacts to Purge",
            "3.45GB, 10 selected",
            "➤ ○ ┌ ~/Developer/write-app      7.07GB | DerivedData | <1d",
            "  ● └ ~/Developer/write-app         8KB | .build | 4d",
            "",
            "Project: ~/Developer/write-app · 9.54GB · 0/3 selected",
            "Path: ~/Developer/write-app/DerivedData",
            "",
            "↑↓ [] Projects / Find | Space Select | Enter Confirm | Q Quit",
        ]
        let menu = try #require(MenuParser.parse(lines: lines))
        #expect(menu.title == "Select Artifacts to Purge")
        #expect(menu.focusedPath == "~/Developer/write-app/DerivedData")

        let item = MenuItem.parse(row: menu.rows[0], index: 0)
        #expect(item.name == "~/Developer/write-app")
        #expect(item.tag == "DerivedData")
        #expect(item.age == "<1d")
        #expect(MenuItem.parse(row: menu.rows[1], index: 1).preselected)
    }

    @Test func focusedPathMustAgreeWithItsRow() {
        func item(_ name: String, tag: String?) -> MenuItem {
            MenuItem(index: 0, rowText: "", name: name, sizeText: nil, bytes: 0, tag: tag, age: nil, path: nil, preselected: false)
        }
        #expect(MenuDriver.path("~/p/app/.build", matches: item("~/p/app", tag: ".build")))
        #expect(MenuDriver.path("~/p/app/Core/.build", matches: item("~/p/app", tag: "Core/.build")))
        #expect(MenuDriver.path("~/p/app/apps/nudge-desktop/target", matches: item("~/p/app", tag: "apps/nudge...")))
        // The previous row's path, still on screen just after the cursor moved.
        #expect(!MenuDriver.path("~/p/app/DerivedData", matches: item("~/p/app", tag: ".build")))
        #expect(!MenuDriver.path("~/p/other/.build", matches: item("~/p/app", tag: ".build")))
    }

    @Test func runSummariesReadTheClosingLine() throws {
        let clean = try #require(RunSummary.parse(lines: ["✓ Cache · 2 items, 1MB", "Space freed: 2.02GB | Items cleaned: 85"]))
        #expect(clean.bytes == 2_020_000_000)
        #expect(!clean.isEstimate)
        #expect(RunSummary.parse(lines: ["Removed 1 app, freed 8KB: Dummy"])?.bytes == 8_000)
        #expect(RunSummary.parse(lines: ["Estimated space freed: 1.0MB | Items: 1"])?.sizeText == "1.0MB")
        #expect(RunSummary.parse(lines: ["Would free approximately: 3.45GB | Items: 10"])?.isEstimate == true)
        #expect(RunSummary.parse(lines: ["Potential space: 1.93GB · 85 items"])?.isEstimate == true)
        #expect(RunSummary.parse(lines: ["✓ Nothing to clean"]) == nil)
        #expect(RunSummary.parse(lines: ["9 apps, 381.7MB of Intel code"])?.isEstimate == true)
    }

    @Test func alignedSizeListingsSplitIntoNameAndSize() {
        let line = LogLine(id: 0, raw: "  Google Chrome        264.3MB")
        #expect(line.title == "Google Chrome")
        #expect(line.detail == "264.3MB")
        #expect(line.bytes == 264_300_000)
    }

    @Test func menuHeaderReportsPositionAndCounts() throws {
        let paged = try #require(MenuParser.parse(lines: [
            "Select Artifacts to Purge [51/120]",
            "3.45GB, 70 selected",
            "➤ ○ ─ ~/p/a   1.0MB | dist | 5mo",
            "↑↓ | Space Select | Enter Confirm",
        ]))
        #expect(paged.position?.current == 51)
        #expect(paged.position?.total == 120)
        #expect(paged.reportedSelectedCount == 70)
        #expect(paged.reportedTotal == 120)

        let slim = try #require(MenuParser.parse(lines: [
            "Select apps to slim  2/9 selected",
            "➤ ● Chrome   264.3MB",
            "↑↓ | Space Select | Enter Save",
        ]))
        #expect(slim.reportedSelectedCount == 2)
        #expect(slim.reportedTotal == 9)
    }

    @Test func aFileNameInARowCannotSupplyCounts() throws {
        let menu = try #require(MenuParser.parse(lines: [
            "Select Installers",
            "➤ ○ 7 selected [9/9].dmg   1.0MB | Downloads",
            "↑↓ | Space Select | Enter Confirm",
        ]))
        #expect(menu.reportedSelectedCount == nil)
        #expect(menu.position == nil)
    }

    @Test func outputWithoutKeyHintsIsNeverAMenu() {
        #expect(MenuParser.parse(lines: ["  ○ User app cache · 4 items", "  ● something"]) == nil)
    }

    @Test func versionOutputParses() throws {
        let output = "Mole version 1.69.0\nmacOS: 27.2\nInstall: Homebrew\n"
        let info = try #require(CLILocator.parseVersionOutput(output, executable: "/nonexistent/mo"))
        #expect(info.version == "1.69.0")
        #expect(info.installMethod == "Homebrew")
    }
}

@Suite struct JSONDecodingTests {
    @Test func statusDecodesNullsAndUnknownFields() throws {
        let json = #"""
        {"host":"m","health_score":100,"health_score_msg":"Excellent","future_field":{"a":1},
         "cpu":{"usage":17.3,"per_core":[1.5,2.5],"p_core_count":6},
         "memory":{"used":1,"total":2,"used_percent":50.0,"pressure":""},
         "batteries":null,"gpu":[{"name":"G","usage":-1}],
         "disks":[{"mount":"/data","used":1,"total":2},{"mount":"/","used":3,"total":4}],
         "network":[{"name":"en0","rx_rate_mbs":1.5,"tx_rate_mbs":0.5},{"name":"en1","rx_rate_mbs":0.5,"tx_rate_mbs":0.5}],
         "top_processes":[{"pid":1,"name":"launchd","cpu":0.1,"memory_bytes":1024}]}
        """#
        let snapshot = try StatusSnapshot.decode(Data(json.utf8))
        #expect(snapshot.healthScore == 100)
        #expect(snapshot.cpu?.perCore?.count == 2)
        #expect(snapshot.cpu?.pCoreCount == 6)
        #expect(snapshot.batteries == nil)
        #expect(snapshot.rootDisk?.mount == "/")
        #expect(snapshot.totalDownload == 2.0)
        #expect(snapshot.topProcesses?.first?.memoryBytes == 1024)
    }

    @Test func analyzeDecodes() throws {
        let json = #"""
        {"scan_status":"partial","path":"/","overview":true,"total_size":10,
         "entries":[{"scan_status":"complete","name":"Home","path":"/Users/a","size":10,"is_dir":true,"cleanable":true}],
         "large_files":[{"name":"x","path":"/x","size":5}]}
        """#
        let result = try AnalyzeResult.decode(Data(json.utf8))
        #expect(result.isPartial)
        #expect(result.entries?.first?.isDir == true)
        #expect(result.entries?.first?.cleanable == true)
    }

    @Test func historyDecodes() throws {
        let json = #"""
        {"logs":{"operations":"/o","deletions":"/d"},"limit":3,
         "sessions":[{"command":"clean-dry-run","run_id":"1","started_at":"2026","items":3,"size":"1GB",
                      "actions":{"removed":0,"skipped":1}}],
         "deletions":[{"timestamp":"t","mode":"trash","status":"ok","size_kb":null,"path":"/p"}]}
        """#
        let report = try HistoryReport.decode(Data(json.utf8))
        #expect(report.sessions?.first?.isPreview == true)
        #expect(report.sessions?.first?.commandName == "clean")
        #expect(report.deletions?.first?.sizeKb == nil)
    }

    @Test func historyDeletionBytesPreserveMissingSizesAndSaturateOverflow() throws {
        let cases: [(kilobytes: Int64?, bytes: Int64?)] = [
            (nil, nil), (0, 0), (1, 1_024), (-1, -1_024),
            (.max / 1_024, .max - 1_023), (.max / 1_024 + 1, .max),
            (.min / 1_024, .min), (.min / 1_024 - 1, .min),
            (.max, .max), (.min, .min),
        ]
        for item in cases {
            let value = item.kilobytes.map(String.init) ?? "null"
            let json = "{\"deletions\":[{\"size_kb\":\(value)}]}"
            let report = try HistoryReport.decode(Data(json.utf8))
            let deletion = try #require(report.deletions?.first)
            #expect(deletion.bytes == item.bytes)
        }
    }

    @Test func aSaturatedLoggedSizeCanBeDisplayedInHistory() throws {
        let home = TestScratch.root + "burrow-history-log-" + UUID().uuidString
        let log = OperationsLog(home: home, command: "analyze", environment: [:])
        log.recordTrashed(path: "/fixture/saturated", size: .max)
        #expect(!log.writeFailed)
        let text = try String(contentsOfFile: home + "/Library/Logs/mole/deletions.log", encoding: .utf8)
        let fields = text.trimmingCharacters(in: .newlines).split(separator: "\t")
        try #require(fields.count == 5)
        #expect(fields[2] == "9007199254740992")
        let json = "{\"deletions\":[{\"size_kb\":\(fields[2])}]}"
        let report = try HistoryReport.decode(Data(json.utf8))
        #expect(report.deletions?.first?.bytes == .max)
    }

    @Test func uninstallListDecodes() throws {
        let json = #"[{"name":"Claude","bundle_id":"com.x","source":"App","uninstall_name":"Claude","path":"/Applications/Claude.app","size":"--"}]"#
        let apps = try InstalledApp.decodeList(Data(json.utf8))
        #expect(apps.first?.uninstallName == "Claude")
        #expect(apps.first?.bundleId == "com.x")
    }
}

@Suite struct UninstallTargetingTests {
    private func app(_ name: String, _ path: String?, uninstallName: String? = nil) throws -> InstalledApp {
        let fields: [String: Any?] = ["name": name, "path": path, "uninstall_name": uninstallName ?? name]
        let data = try JSONSerialization.data(withJSONObject: [fields.compactMapValues { $0 }])
        return try #require(try InstalledApp.decodeList(data).first)
    }

    @Test func aSharedNameFallsBackToTheFolderOnlyThatAppAnswersTo() throws {
        let stable = try app("Xcode", "/Applications/Xcode.app")
        let beta = try app("Xcode", "/Applications/Xcode-beta.app")
        let all = [stable, beta]
        #expect(UninstallTargeting.terms(for: [beta], among: all) == ["Xcode-beta"])
        // Nothing singles this one out, so the plan check decides whether it can go ahead.
        #expect(UninstallTargeting.terms(for: [stable], among: all) == ["Xcode"])
        #expect(UninstallTargeting.terms(for: [stable, beta], among: all) == ["Xcode", "Xcode-beta"])
    }

    @Test func aUniqueNameIsPassedAsIs() throws {
        let claude = try app("Claude", "/Applications/Claude.app")
        let other = try app("Notes App", "/Applications/Notes App.app")
        #expect(UninstallTargeting.terms(for: [claude, other], among: [claude, other]) == ["Claude", "Notes App"])
    }

    @Test func aCaskNameTheMatcherCantFindGivesWayToTheDisplayName() throws {
        let chrome = try app("Google Chrome", "/Applications/Google Chrome.app", uninstallName: "google-chrome")
        #expect(UninstallTargeting.terms(for: [chrome], among: [chrome]) == ["Google Chrome"])
    }

    @Test func aFolderMatchingAnotherAppsNameIsNotUnique() throws {
        let renamed = try app("Tool", "/Applications/Helper.app")
        let helper = try app("Helper", "/Applications/Other.app")
        // "Tool" is unique, but "Helper" also names the first app's folder.
        let terms = UninstallTargeting.terms(for: [renamed, helper], among: [renamed, helper])
        #expect(terms == ["Tool", "Other"])
    }

    @Test func matchingIgnoresCaseButPreservesTheChosenSpelling() throws {
        let first = try app("Tool", "/Applications/TOOL.APP")
        let second = try app("tool", "/Applications/Other.app")
        #expect(UninstallTargeting.terms(for: [first, second], among: [first, second]) == ["TOOL", "Other"])
    }

    @Test func aMissingPathStillUsesTheNameOrUninstallFallback() throws {
        let listed = try app("No Path", nil, uninstallName: "no-path")
        let missing = try app("Missing", nil, uninstallName: "missing-cask")
        #expect(UninstallTargeting.terms(for: [listed, missing], among: [listed]) == ["No Path", "missing-cask"])
    }

    @Test func duplicateIdentityDoesNotMakeAnAmbiguousWordUnique() throws {
        let listed = try app("Tool", "/Applications/Other.app")
        // Repeated selected entries retain their order; repeated matches remain ambiguous.
        #expect(UninstallTargeting.terms(for: [listed, listed], among: [listed]) == ["Tool", "Tool"])
        #expect(UninstallTargeting.terms(for: [listed], among: [listed, listed]) == ["Other"])
    }
}

@Suite struct UninstallPlanTests {
    private let plan = [
        "◎ Matched 2 app(s):",
        "1. Xcode  3.98GB  |  Last: 6d ago",
        "Files to be removed:",
        "◎ Xcode , 3.98GB",
        "  ◎ A leftover note",
        "  ✓ /Applications/Xcode-beta.app , 3.98GB",
        "  ✓ ~/Library/Caches/com.apple.dt.Xcode , 1GB",
        "◎ Tool [Brew] , 80KB",
        "  ✓ ~/Applications/Tool.app",
        "  ◎ Review only: /Library/Logs/x.app",
        "Personal data kept:",
        "  ⊙ /var/folders/x",
        "D choose personal data",
    ]

    @Test func readsOnlyEachAppsOwnPath() {
        #expect(UninstallPlan.appPaths(in: plan, home: "/Users/me") == ["/Applications/Xcode-beta.app", "/Users/me/Applications/Tool.app"])
    }

    @Test func aMissingPlanReadsAsEmptySoItCantPassAsAMatch() {
        #expect(UninstallPlan.appPaths(in: ["◎ Xcode , 3.98GB", "  ✓ /Applications/Xcode.app"], home: "/h").isEmpty)
    }

    @Test func theLatestPlanWinsWhenTheCLIPrintsItAgain() {
        let lines = ["Files to be removed:", "◎ Old", "  ✓ /Applications/Old.app", "Files to be removed:", "◎ New", "  ✓ /Applications/New.app"]
        #expect(UninstallPlan.appPaths(in: lines, home: "/h") == ["/Applications/New.app"])
    }
}

struct CLIOutputKnowledgeTests {
    @Test func touchIDStatusIsReadFromTheCLIsWording() throws {
        let off = try #require(TouchIDStatus(output: "\u{1B}[0;33m◎\u{1B}[0m Touch ID is not configured\n"))
        #expect(off.description == "Touch ID is not configured")
        #expect(!off.isEnabled)
        let on = try #require(TouchIDStatus(output: "✓ Touch ID is enabled\n"))
        #expect(on.description == "Touch ID is enabled")
        #expect(on.isEnabled)
        #expect(TouchIDStatus(output: " \n") == nil)
    }

    @Test(arguments: ["Clean Your Mac", "Dry Run Mode", "○ DRY RUN MODE - nothing changes", "Optimize", "◎ Enter your credentials below"])
    func bannersAreChatter(line: String) {
        #expect(LogLine.isChatter(line))
    }

    @Test func rowsAreNotChatter() {
        #expect(!LogLine.isChatter("  ✓ Cleaned user cache · 2MB"))
        #expect(!LogLine.isChatter("  Optimize caches"))
    }

    @Test func statusLinesSplitAcrossChunksAreJoined() {
        let parser = NDJSONParser()
        #expect(parser.feed(Data(#"{"host":"a"#.utf8)).isEmpty)
        #expect(parser.takeRejectedLines() == 0)
        let snapshots = parser.feed(Data(#"bc"}"#.utf8) + Data("\nnot json\n\n".utf8))
        #expect(snapshots.map(\.host) == ["abc"])
        #expect(parser.takeRejectedLines() == 1)
        #expect(parser.takeRejectedLines() == 0)
    }
}

struct PromptWordingTests {
    @Test(arguments: [
        ("Remove 1 app, 682.6MB  Enter confirm, ESC cancel:", "Remove 1 app, 682.6MB", "Remove"),
        ("Press Enter to enable, ESC to cancel:", "Enable", "Enable"),
        ("Delete these? Enter confirm, Q quit:", "Delete these?", "Delete"),
        ("Do the thing:", "Do the thing", "Confirm"),
    ])
    func questionsAndButtonTitlesComeFromTheCLIsWording(text: String, question: String, title: String) {
        #expect(CLIPrompt.question(from: text) == question)
        #expect(CLIPrompt.confirmTitle(from: text) == title)
    }

    @Test func spinnerLinesAreRecognized() {
        #expect("⠴ Scanning".startsWithSpinner)
        #expect(!"Scanning".startsWithSpinner)
        #expect(!"".startsWithSpinner)
    }
}
