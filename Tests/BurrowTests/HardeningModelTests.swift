import Foundation
import SwiftUI
import Testing
import BurrowCore
@testable import Burrow

@MainActor
@Suite(.timeLimit(.minutes(2)))
struct MenuFlowModelTests {
    /// A stand-in for a CLI selection menu with a preselected row.
    private func menuCLI() throws -> (CLIInfo, String) {
        try makeScript(#"""
        #!/bin/bash
        selected=(0 0 1); cursor=0
        stty -echo -icanon
        draw() {
          printf '\033[H\033[2J'
          local count=0; for s in "${selected[@]}"; do count=$((count+s)); done
          printf 'Select Things [%d/3], %d selected\r\n\r\n' "$((cursor+1))" "$count"
          local i
          for ((i=0; i<3; i++)); do
            local mark='○'; [[ ${selected[i]} == 1 ]] && mark='●'
            if [[ $i == "$cursor" ]]; then printf '➤ %s row%d   1.0MB\r\n' "$mark" "$i"
            else printf '  %s row%d   1.0MB\r\n' "$mark" "$i"; fi
          done
          printf '\r\n↑↓ | Space Select | Enter Confirm | Q Quit\r\n'
        }
        while true; do
          draw
          IFS= read -rsn1 key
          if [[ $key == $'\033' ]]; then
            read -rsn2 rest
            [[ $rest == '[B' && $cursor -lt 2 ]] && cursor=$((cursor+1))
            [[ $rest == '[A' && $cursor -gt 0 ]] && cursor=$((cursor-1))
          elif [[ $key == ' ' ]]; then
            selected[cursor]=$((1-selected[cursor]))
          elif [[ $key == '' ]]; then
            printf '%s' "${selected[*]}" > "$(dirname "$0")/result"
            exit 0
          elif [[ $key == q ]]; then
            exit 2
          fi
        done
        """#)
    }

    private func choosing(policy: ExecutionPolicy, cli: CLIInfo) async throws -> MenuFlowModel {
        let model = MenuFlowModel(configuration: .installers, policy: policy)
        model.scan(cli: cli, preview: false)
        try await eventually { model.state == .choosing }
        return model
    }

    @Test func onlyTheChosenRowsAreConfirmed() async throws {
        let (cli, directory) = try menuCLI()
        let model = try await choosing(policy: .live, cli: cli)
        #expect(model.items.count == 3)
        #expect(model.selection == [2])
        #expect(model.run.isIrreversible)
        #expect(model.run.consequence?.contains("permanently") == true)
        model.selection = [1]
        model.applySelection(preview: false)
        try await eventually { !model.run.isRunning }
        let result = try String(contentsOfFile: directory + "/result", encoding: .utf8)
        #expect(result == "0 1 0")
        model.finishRun()
    }

    @Test func aMenuStartedForRealCantBeConfirmedInPreview() async throws {
        let (cli, directory) = try menuCLI()
        let model = try await choosing(policy: .live, cli: cli)
        model.applySelection(preview: true)
        #expect(model.state == .idle)
        #expect(model.errorMessage?.contains("Preview") == true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: directory + "/result"))
    }

    @Test func turningOnPreviewWhileApplyingConfirmsNothing() async throws {
        let (cli, directory) = try menuCLI()
        let policy = ExecutionPolicy.live
        let model = try await choosing(policy: policy, cli: cli)
        model.selection = [0, 1]
        model.applySelection(preview: false)
        policy.previewMode = true
        try await eventually { model.state == .idle }
        #expect(model.errorMessage?.contains("Preview") == true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: directory + "/result"))
    }

    @Test func leavingTheListConfirmsNothing() async throws {
        let (cli, directory) = try menuCLI()
        let model = try await choosing(policy: .live, cli: cli)
        model.abandonSelection()
        #expect(model.state == .idle)
        #expect(model.items.isEmpty)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: directory + "/result"))
    }

    @Test func aPreviewCarriesNoConsequence() async throws {
        let (cli, _) = try menuCLI()
        let model = MenuFlowModel(configuration: .installers, policy: ExecutionPolicy(defaults: nil, forced: true))
        model.scan(cli: cli, preview: true)
        #expect(model.run.consequence == nil)
        model.shutdown()
    }

    @Test func onlyReversibleFlowsCanConfirmWithReturn() {
        #expect(MenuFlowConfiguration.purge.isIrreversible)
        #expect(MenuFlowConfiguration.installers.isIrreversible)
        #expect(!MenuFlowConfiguration.slim.isIrreversible)
    }
}

@MainActor
struct ManageModelTests {
    private func fixture() -> (ManageModel, ScriptedCommands) {
        let commands = ScriptedCommands()
        return (ManageModel(policy: .live, commands: commands.client), commands)
    }

    @Test func readsTheCurrentStatus() async throws {
        let (model, commands) = fixture()
        model.refresh(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        await commands.completeRun(0, stdout: "◎ Touch ID is not configured\n")
        try await eventually { !model.touchIDStatus.isEmpty }
        #expect(model.touchIDStatus == "Touch ID is not configured")
        #expect(model.touchIDEnabled == false)
    }

    @Test func aFailedCheckDoesntKeepSayingChecking() async throws {
        let (model, commands) = fixture()
        model.refresh(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        await commands.failRun(0)
        try await eventually { !model.touchIDStatus.isEmpty }
        #expect(model.touchIDStatus == "Couldn’t check")
        #expect(model.touchIDEnabled == nil)
    }

    @Test func anOlderCheckCantReplaceANewerOne() async throws {
        let (model, commands) = fixture()
        model.refresh(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        model.refresh(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 2 }
        await commands.completeRun(1, stdout: "✓ Touch ID is enabled\n")
        try await eventually { model.touchIDEnabled == true }
        await commands.completeRun(0, stdout: "◎ Touch ID is not configured\n")
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.touchIDEnabled == true)
    }

    @Test func aRealCommandIsRefusedInPreview() {
        let model = ManageModel(policy: ExecutionPolicy(defaults: nil, forced: true))
        model.perform(title: "Removing Mole", arguments: ["remove"], cli: fixtureCLI)
        guard case .failedToStart = model.run.phase else {
            Issue.record("Expected Preview Mode to refuse the command")
            return
        }
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PasswordPathTests {
    @Test func aPasswordReachesTheCommandOnlyWithEchoOff() async throws {
        let (cli, directory) = try makeScript("""
        #!/bin/bash
        stty -echo
        printf 'Password:'
        IFS= read -r secret
        printf '%s' "$secret" > "$(dirname "$0")/received"
        """)
        let run = RunController(policy: .live)
        run.start(title: "Fixture", cli: cli, arguments: [])
        try await eventually {
            if case .password = run.promptRequest?.prompt { return true }
            return false
        }
        run.answerPassword("correct horse")
        #expect(run.promptRequest == nil)
        try await eventually { FileManager.default.fileExists(atPath: directory + "/received") }
        try await eventually { !run.isRunning }
        #expect(try String(contentsOfFile: directory + "/received", encoding: .utf8) == "correct horse")
        #expect(!run.lines.contains { $0.text.contains("correct horse") })
    }

    @Test func nothingIsSentWhileEchoIsOn() async throws {
        let (cli, directory) = try makeScript("""
        #!/bin/bash
        printf 'ready\\r\\n'
        IFS= read -t 1 -r line
        printf '%s' "$line" > "$(dirname "$0")/received"
        """)
        let run = RunController(policy: .live)
        run.start(title: "Fixture", cli: cli, arguments: [])
        try await eventually { !run.lines.isEmpty }
        run.promptRequest = PromptRequest(prompt: .password("Password:"))
        run.answerPassword("must not appear")
        #expect(run.promptRequest == nil)
        try await eventually { !run.isRunning }
        #expect(try String(contentsOfFile: directory + "/received", encoding: .utf8).isEmpty)
    }

    @Test func aPromptWithEchoOnDoesntAskForAPassword() async throws {
        let (cli, _) = try makeScript("#!/bin/bash\nprintf 'Password:'\nsleep 5\n")
        let run = RunController(policy: .live)
        run.start(title: "Fixture", cli: cli, arguments: [])
        try await eventually { run.terminal?.partial.contains("Password") == true }
        try await Task.sleep(for: .milliseconds(500))
        #expect(run.promptRequest == nil)
        run.cancel()
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RunOutputTests {
    @Test func aLongListingKeepsItsLastRowsAndSaysWhatsHidden() async throws {
        let (cli, _) = try makeScript("#!/bin/bash\nfor ((i=0; i<20100; i++)); do echo \"  ✓ row$i\"; done\n")
        let run = RunController(policy: .live)
        run.start(title: "Fixture", cli: cli, arguments: [])
        while run.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        #expect(run.lines.count == 20_000)
        #expect(run.hiddenLineCount == 100)
        #expect(run.lines.last?.text.contains("row20099") == true)
    }

    @Test func everyRowIsVisibleByTheTimeACommandEnds() async throws {
        let (cli, _) = try makeScript("#!/bin/bash\necho '  ✓ only row'\n")
        let run = RunController(policy: .live)
        run.start(title: "Fixture", cli: cli, arguments: [])
        try await eventually { !run.isRunning }
        #expect(run.lines.map(\.title) == ["only row"])
        #expect(run.completionAnnouncement == "Done.")
    }

    @Test func thePlanIsCompleteWhenTheQuestionAppears() async throws {
        let (cli, _) = try makeScript("""
        #!/bin/bash
        echo '  ✓ planned item'
        printf 'Remove 1 app, 1GB  Enter confirm, ESC cancel: '
        IFS= read -r -s -n1 key
        """)
        let run = RunController(policy: .live)
        run.start(title: "Fixture", cli: cli, arguments: [], consequence: "Gone for good.", isIrreversible: true)
        try await eventually { run.promptRequest != nil }
        #expect(run.lines.map(\.title) == ["planned item"])
        #expect(run.consequence == "Gone for good.")
        #expect(run.isIrreversible)
        run.cancel()
        try await eventually { !run.isRunning }
        #expect(run.completionAnnouncement == "Fixture cancelled.")
        run.reset()
        #expect(run.consequence == nil)
        #expect(!run.isIrreversible)
    }
}

@MainActor
struct PreviewToggleTests {
    private func model() -> AppModel {
        AppModel(defaults: nil, environment: [:], locator: { _ in nil })
    }

    @Test func aRealRunBlocksTurningPreviewOn() async {
        let model = model()
        #expect(model.isPreviewToggleEnabled)
        model.clean.requestExternalClean(path: "/Volumes/Fixture", cli: sleeperCLI, preview: false)
        model.clean.confirmExternalClean(cli: sleeperCLI)
        #expect(model.hasWorkChangingTheMac)
        #expect(!model.isPreviewToggleEnabled)
        #expect(model.previewToggleHelp.contains("Finish or cancel"))
        model.clean.finishRun()
        #expect(model.isPreviewToggleEnabled)
        await model.shutdown(lifecycle: ProcessLifecycle())
    }

    @Test func aPreviewRunDoesnt() async {
        let model = model()
        model.optimize.runMaintenance(cli: sleeperCLI, preview: true)
        #expect(!model.hasWorkChangingTheMac)
        #expect(model.isPreviewToggleEnabled)
        await model.shutdown(lifecycle: ProcessLifecycle())
    }

    @Test func aScanWaitingAtAMenuDoesnt() async {
        let model = model()
        model.purge.scan(cli: sleeperCLI, preview: false)
        #expect(model.purge.state == .scanning)
        #expect(model.purge.run.isRunning)
        #expect(!model.hasWorkChangingTheMac)
        #expect(model.isPreviewToggleEnabled)
        await model.shutdown(lifecycle: ProcessLifecycle())
    }

    @Test func previewCanAlwaysBeTurnedOffUnlessForced() {
        let forced = AppModel(defaults: nil, environment: ["BURROW_FORCE_PREVIEW": "1"], locator: { _ in nil })
        #expect(!forced.isPreviewToggleEnabled)
        let model = model()
        model.previewMode = true
        #expect(model.isPreviewToggleEnabled)
    }

    @Test func everyRunIsReachableForCancellation() {
        let model = model()
        let expected = [model.clean.run, model.uninstall.run, model.purge.run, model.installers.run, model.slim.run, model.optimize.run, model.manage.run]
        #expect(model.allRuns.count == expected.count)
        for run in expected {
            #expect(model.allRuns.contains { $0 === run })
        }
    }
}

/// A pinned notice once measured as a column taller than the window, which pushed the
/// whole window's content out of view.
@MainActor
struct NoticeBarLayoutTests {
    @Test func aLongNoticeStaysShortAtTheNarrowWidthsAWindowMeasures() {
        let text = String(repeating: "A long sentence about what this version of the CLI means. ", count: 6)
        let controller = NSHostingController(rootView: NoticeBar(text: text) {})
        for width in [CGFloat(1), 20, 100, 400] {
            let size = controller.sizeThatFits(in: CGSize(width: width, height: 10_000))
            #expect(size.height < 120)
        }
    }
}

@MainActor
struct CustomCLIChoiceTests {
    @Test func aChoiceThatCantBeUsedSaysSo() async {
        let other = CLIInfo(executable: "/opt/homebrew/bin/mo", root: "/", version: "1", installMethod: "test")
        let model = AppModel(defaults: nil, environment: [:], locator: { _ in other })
        await model.useCustomCLI(path: "/Users/me/not-mole")
        #expect(model.cliChoiceError?.contains("not-mole") == true)
        await model.useCustomCLI(path: "/opt/homebrew/bin/mo")
        #expect(model.cliChoiceError == nil)
        await model.shutdown(lifecycle: ProcessLifecycle())
    }
}

@MainActor
struct CleanConfirmationTests {
    @Test func theTrashIsNamedWhenItWouldBeEmptied() {
        let report = CleanReport.parse(preview: "➤ User essentials\n  ○ Trash · would empty, 3 items\n", pathList: nil)
        #expect(CleanModel.confirmationMessage(for: report).contains("permanently empties your Trash"))
    }

    @Test func otherwiseItStillDoesntPromiseOnlyCaches() {
        let message = CleanModel.confirmationMessage(for: CleanReport())
        #expect(message.contains("not only caches"))
        #expect(!message.contains("Caches rebuild"))
        #expect(!message.contains("Trash"))
    }
}

@MainActor
struct DeadlineTests {
    @Test func workThatFinishesReportsSo() async {
        var ran = false
        #expect(await finishes(within: .seconds(5)) { ran = true })
        #expect(ran)
    }

    @Test func workStuckPastTheDeadlineDoesntHoldUpTheCaller() async {
        let start = ContinuousClock.now
        let finished = await finishes(within: .milliseconds(50)) {
            try? await Task.sleep(for: .seconds(30))
        }
        #expect(!finished)
        #expect(start.duration(to: .now) < .seconds(5))
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct StalePageTests {
    @Test func aRealCommandReportsItsChangesAndAPreviewDoesnt() async throws {
        let (cli, _) = try makeScript("#!/bin/bash\nexit 0\n")
        for (arguments, expected) in [([String](), true), (["--dry-run"], false)] {
            let run = RunController(policy: .live)
            var reported = false
            run.onFinishedChanges = { reported = true }
            run.start(title: "Fixture", cli: cli, arguments: arguments)
            try await eventually { !run.isRunning }
            #expect(reported == expected)
        }
    }

    @Test func aDeclinedQuestionChangedNothing() async throws {
        let (cli, _) = try makeScript("""
        #!/bin/bash
        printf 'Remove 1 app, 1GB  Enter confirm, ESC cancel: '
        IFS= read -r -s -n1 key
        """)
        let run = RunController(policy: .live)
        var reported = false
        run.onFinishedChanges = { reported = true }
        run.start(title: "Fixture", cli: cli, arguments: [])
        try await eventually { run.promptRequest != nil }
        run.answerDecline()
        try await eventually { !run.isRunning }
        #expect(!reported)
    }

    @Test func aCancelledCleanupMayHaveChangedThings() async throws {
        let (cli, _) = try makeScript("#!/bin/bash\nsleep 30\n")
        let run = RunController(policy: .live)
        var reported = false
        run.onFinishedChanges = { reported = true }
        run.start(title: "Fixture", cli: cli, arguments: [])
        run.cancel()
        try await eventually { !run.isRunning }
        #expect(reported)
    }

    private func analyze() -> (AnalyzeModel, Scans) {
        let scans = Scans()
        let json = #"{"path":"/fixture","entries":[{"name":"a","path":"/fixture/a","size":1,"is_dir":false},{"name":"System","path":"/System","size":1,"is_dir":true}]}"#
        let model = AnalyzeModel(
            policy: .live,
            commands: CommandClient(run: { _, _, _ in
                await scans.note()
                return CommandResult(status: 0, stdout: json, stderr: "")
            }),
            home: "/fixture"
        )
        return (model, scans)
    }

    private actor Scans {
        private(set) var count = 0
        func note() { count += 1 }
    }

    @Test func diskExplorerScansAgainOnlyAfterAnotherPageChangedTheDisk() async throws {
        let (model, scans) = analyze()
        model.openRoot(cli: fixtureCLI)
        try await eventually { !model.isLoading && !model.entries.isEmpty }
        #expect(await scans.count == 1)
        model.openRoot(cli: fixtureCLI)
        try await Task.sleep(for: .milliseconds(30))
        #expect(await scans.count == 1)

        model.markStale()
        model.openRoot(cli: fixtureCLI)
        try await eventually { await scans.count == 2 }
        try await eventually { !model.isLoading }
        model.openRoot(cli: fixtureCLI)
        try await Task.sleep(for: .milliseconds(30))
        #expect(await scans.count == 2)
    }

    @Test func aProtectedListSelectionSaysWhyThereIsNoTrashAction() async throws {
        let (model, _) = analyze()
        model.openRoot(cli: fixtureCLI)
        try await eventually { !model.isLoading && !model.entries.isEmpty }
        model.noteSelection(added: ["/fixture/a"])
        #expect(model.noticeMessage == nil)
        model.noteSelection(added: ["/System"])
        #expect(model.noticeMessage?.contains("System is protected") == true)
    }

    @Test func uninstallReadsTheListAgainOnlyWhenItsOutOfDate() async throws {
        let commands = ScriptedCommands()
        let model = UninstallModel(
            policy: .live,
            commands: commands.client,
            sizeClient: AppSizeClient(measure: { _ in 1 }),
            home: "/fixture"
        )
        model.loadIfNeeded(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        await commands.completeRun(0, stdout: "[]")
        try await eventually { model.state == .list }

        model.loadIfNeeded(cli: fixtureCLI)
        try await Task.sleep(for: .milliseconds(30))
        #expect(await commands.runs.count == 1)

        model.markStale()
        model.loadIfNeeded(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 2 }
        await commands.completeRun(1, stdout: "[]")
    }

    @Test func aCancelledFlowScanDoesntMarkAnythingStale() async throws {
        // AppModel builds its own disk page, so it reads this stand-in. A scan of the disk
        // answers at once, and a flow's command runs until it's stopped.
        let (cli, _) = try makeScript("""
        #!/bin/bash
        [[ $1 == analyze ]] && { printf '{"path":"/fixture","entries":[]}'; exit 0; }
        exec /bin/sleep 30
        """)
        let model = AppModel(defaults: nil, environment: [:], locator: { _ in nil })
        model.analyze.openRoot(cli: cli)
        try await eventually { !model.analyze.isLoading }
        try #require(model.analyze.result != nil)

        model.purge.scan(cli: cli, preview: false)
        model.purge.cancelScan()
        #expect(model.purge.state == .idle)
        // A run reports its changes in the same step that it stops running.
        try await eventually { !model.purge.run.isRunning }

        // Reopening the page starts a new scan, there and then, only if it's stale.
        model.analyze.openRoot(cli: cli)
        #expect(!model.analyze.isLoading)
        model.analyze.markStale()
        model.analyze.openRoot(cli: cli)
        #expect(model.analyze.isLoading)
        await model.shutdown(lifecycle: ProcessLifecycle())
    }

    @Test func commandDeleteOnlyActsInDiskExplorer() {
        let model = AppModel(defaults: nil, environment: [:], locator: { _ in nil })
        model.selection = .clean
        #expect(model.trashAction == nil)
    }
}

struct StatusTintTests {
    @Test func aLowBatteryChangesColorUnlessItsCharging() {
        #expect(StatusTint.battery(percent: 3, status: "discharging") == .red)
        #expect(StatusTint.battery(percent: 18, status: "discharging") == .orange)
        #expect(StatusTint.battery(percent: 80, status: "discharging") == .green)
        #expect(StatusTint.battery(percent: 3, status: "charging") == .green)
        #expect(StatusTint.battery(percent: nil, status: nil) == .green)
    }

    @Test func gpuLoadChangesColorAsItRises() {
        #expect(StatusTint.load(10) == .accentColor)
        #expect(StatusTint.load(75) == .orange)
        #expect(StatusTint.load(95) == .red)
    }
}

struct LogFollowSettlingTests {
    @Test func layoutMovingTheOffsetAtFirstDoesntStopFollowing() {
        var follow = LogFollowState()
        follow.updateViewport(offset: 100, contentHeight: 5_000, viewportHeight: 500, movedUp: true)
        #expect(follow.isFollowing)
        follow.finishSettling()
        follow.updateViewport(offset: 80, contentHeight: 5_000, viewportHeight: 500, movedUp: true)
        #expect(!follow.isFollowing)
    }

    @Test func aScrollEndsSettlingSoALaterUpwardMoveCounts() {
        var follow = LogFollowState()
        follow.updateViewport(offset: 4_500, contentHeight: 5_000, viewportHeight: 500)
        follow.userScrolling(true)
        follow.userScrolling(false)
        #expect(follow.isFollowing)
        follow.updateViewport(offset: 4_000, contentHeight: 5_000, viewportHeight: 500, movedUp: true)
        #expect(!follow.isFollowing)
    }
}

/// With more than the map's tile limit, the "small items" tile takes up room. The rectangle a
/// folder grows from once ignored it, so the animation started away from the tile.
@MainActor
struct ZoomOriginTests {
    @Test(arguments: [CGSize(width: 800, height: 400), CGSize(width: 400, height: 800)])
    func aFolderGrowsFromWhereItsTileIsDrawn(size: CGSize) async throws {
        let rows = (0..<40).map { #"{"name":"e\#($0)","path":"/fixture/e\#($0)","size":\#(1_000 - $0),"is_dir":true}"# }
        let json = #"{"path":"/fixture","entries":["# + rows.joined(separator: ",") + "]}"
        let model = AnalyzeModel(
            policy: .live,
            commands: CommandClient(run: { _, _, _ in CommandResult(status: 0, stdout: json, stderr: "") }),
            home: "/fixture"
        )
        model.openRoot(cli: fixtureCLI)
        try await eventually { !model.isLoading && !model.entries.isEmpty }
        model.mapSize = size
        let entry = model.entries[1]
        let origin = try #require(model.tileRect(for: entry))
        let map = EntryMap(entries: model.entries, in: CGRect(origin: .zero, size: size))
        #expect(map.restCount == 8)
        let tile = try #require(map.tiles.first { $0.id == entry.path })
        #expect(origin == EntryMap.normalized(tile.rect, in: size))
        #expect(origin.width * origin.height < 1)
    }
}
