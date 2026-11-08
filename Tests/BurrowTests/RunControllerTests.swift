import Foundation
import Testing
import BurrowCore
@testable import Burrow

@MainActor
struct RunControllerTests {
    @Test func aNewRunCannotReuseSavingsFromThePreviousRun() async throws {
        let run = RunController(policy: .live)
        run.start(title: "First", cli: shellCLI, arguments: ["-c", "printf 'Space freed: 2.02GB\\n'"])
        try await eventually { !run.isRunning }
        #expect(run.summary?.sizeText == "2.02GB")
        run.reset()
        run.start(title: "Second", cli: shellCLI, arguments: ["-c", "printf 'No work today\\n'"])
        try await eventually { !run.isRunning }
        #expect(run.didSucceed)
        #expect(run.summary == nil)
        #expect(run.lines.map(\.title) == ["No work today"])
    }

    @Test func liveAndForcedPreviewRefuseNonPreviewCommandsAtStartup() {
        for forced in [false, true] {
            let policy = ExecutionPolicy(defaults: nil, forced: forced)
            let run = RunController(policy: policy)
            policy.previewMode = !forced
            run.start(title: "Blocked", cli: fixtureCLI, arguments: ["clean"])
            #expect(run.terminal == nil)
            if case .failedToStart(let message) = run.phase {
                #expect(message.contains("Preview Mode"))
            } else {
                Issue.record("An unpreviewed command was admitted")
            }
        }
    }

    @Test func replacedTerminalCannotPublishLateOutputOrExit() async throws {
        let run = RunController(policy: .live)
        run.start(title: "Old", cli: shellCLI, arguments: ["-c", "/bin/sleep 4"])
        let old = try #require(run.terminal)
        let staleLine = old.onLine
        let staleExit = old.onExit
        run.start(title: "Current", cli: shellCLI, arguments: ["-c", "printf 'Current output\\n'"])
        staleLine?("Space freed: 999GB")
        staleExit?(42)
        #expect(run.isRunning)
        try await eventually { !run.isRunning }
        #expect(run.didSucceed)
        #expect(run.summary == nil)
        #expect(run.lines.map(\.title) == ["Current output"])
        _ = await old.waitForExit()
    }

    @Test(arguments: [false, true])
    func cancelledRunDoesNotRaisePromptsDuringTerminationGrace(promptWasVisible: Bool) async throws {
        let run = RunController(policy: .live)
        let question = "Delete 1 item  Enter confirm, ESC cancel:"
        let (cli, directory) = try makeScript("""
        #!/bin/sh
        trap '' INT
        /bin/stty -echo
        printf '\(question)'
        fixture_dir="$(dirname "$0")"
        while [ -d "$fixture_dir" ] && [ ! -f "$fixture_dir/release" ]; do /bin/sleep 0.02; done
        """)
        let release = URL(fileURLWithPath: directory + "/release")
        defer {
            try? Data().write(to: release)
            run.cancel()
            try? FileManager.default.removeItem(atPath: directory)
        }
        run.start(title: "Harmless question", cli: cli, arguments: [])
        let terminal = try #require(run.terminal)
        try await eventually { run.promptRequest != nil }
        if !promptWasVisible {
            // Start a fresh debounce and cancel it without yielding the main actor.
            run.promptRequest = nil
            terminal.resize(rows: 24, columns: 90)
        }

        run.cancel()
        #expect(run.wasCancelled)
        #expect(run.promptRequest == nil)
        if promptWasVisible {
            // Repaints and terminal-panel resizes can happen while cancellation settles.
            terminal.resize(rows: 24, columns: 90)
        }
        try await Task.sleep(for: .milliseconds(600))
        #expect(run.isRunning)
        #expect(run.promptRequest == nil)
        try Data().write(to: release)
        try await eventually { !run.isRunning }
    }
}

@MainActor
struct PendingPreviewPolicyTests {
    @Test func switchingToPreviewCannotConfirmAnAlreadyWaitingLiveCommand() async throws {
        let policy = ExecutionPolicy.live
        let run = RunController(policy: policy)
        run.start(title: "Harmless question", cli: shellCLI,
                  arguments: ["-c", "printf 'Continue? Enter confirm, ESC cancel: '; read answer; printf 'CONFIRMED\\n'"])
        try await eventually { run.promptRequest != nil }
        policy.previewMode = true
        run.answerConfirm()
        try await eventually { !run.isRunning }
        #expect(run.wasCancelled)
        #expect(!run.lines.contains { $0.title == "CONFIRMED" })
    }
}

@MainActor
struct RunLogFilteringTests {
    @Test func aDryRunKeepsTheItemsItWouldChange() async throws {
        let run = RunController(policy: .live)
        run.start(title: "Preview", cli: shellCLI, arguments: ["-c", "printf '➤ Developer tools\\n  ○ npm logs · 4KB dry\\n  ○ Corepack cache · would clean\\n'", "--dry-run"])
        try await eventually { !run.isRunning }
        #expect(run.lines.filter { $0.kind == .preview }.map(\.title) == ["npm logs", "Corepack cache"])
    }

    @Test func aSelectionListOnScreenStaysOutOfTheLog() async throws {
        let run = RunController(policy: .live)
        let script = "printf 'Up Down | Space Select | Enter Confirm\\n'; /bin/sleep 0.2; printf '  ○ row one   1.0MB\\n➤ ○ row two   1.0MB\\n  ● row three   1.0MB\\n'; /bin/sleep 0.2"
        run.start(title: "Menu", cli: shellCLI, arguments: ["-c", script])
        try await eventually { !run.isRunning }
        #expect(run.lines.isEmpty)
    }
}

@MainActor
struct PromptHandoffTests {
    @Test func showingTheTerminalKeepsTheSheetAwayUntilItsHiddenAgain() async throws {
        let run = RunController(policy: .live)
        run.start(title: "Question", cli: shellCLI, arguments: ["-c", "printf 'Delete 1 item  Enter confirm, ESC cancel: '; read answer"])
        try await eventually { run.promptRequest != nil }

        run.showTerminalForPrompt()
        #expect(run.isTerminalVisible)
        #expect(run.promptRequest == nil)
        // Mounting the terminal panel resizes it, which reports the unchanged question again.
        run.terminal?.resize(rows: 24, columns: 90)
        try await Task.sleep(for: .milliseconds(600))
        #expect(run.promptRequest == nil)

        run.isTerminalVisible = false
        try await eventually { run.promptRequest != nil }
        run.cancel()
    }
}
