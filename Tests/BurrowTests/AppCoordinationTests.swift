import Foundation
import os
import Testing
import BurrowCore
@testable import Burrow

private actor Discoveries {
    private(set) var paths: [String?] = []
    private var continuations: [CheckedContinuation<CLIInfo?, Never>] = []
    func locate(_ path: String?) async -> CLIInfo? {
        await withCheckedContinuation {
            paths.append(path)
            continuations.append($0)
        }
    }
    func finish(_ index: Int, cli: CLIInfo?) { continuations[index].resume(returning: cli) }
}

@MainActor
struct AppCoordinationTests {
    @Test func aCleanReviewCannotLaunchAReplacementCLI() async throws {
        let (original, _) = try makeScript("#!/bin/bash\nprintf 'Potential space: 1GB · 1 item\\n'\n")
        let (replacement, directory) = try makeScript("#!/bin/bash\n: > \"$(dirname \"$0\")/launched\"\n")
        let model = AppModel(defaults: nil, environment: [:], locator: { path in
            path == replacement.executable ? replacement : original
        })
        await model.locateCLI()
        model.selection = .clean
        model.clean.scan(cli: original)
        try await eventually { model.clean.state == .review }
        #expect(model.clean.report.potentialBytes == 1_000_000_000)
        let staleAction = try #require(model.primaryAction)
        await model.useCustomCLI(path: "/unavailable/mo")
        #expect(model.cli == original)
        #expect(model.clean.state == .review)
        #expect(model.cliChoiceError != nil)
        await model.useCustomCLI(path: replacement.executable)
        #expect(model.cli == replacement)
        staleAction.perform()
        model.clean.clean(cli: replacement, preview: false)
        if let terminal = model.clean.run.terminal { _ = await terminal.waitForExit() }
        #expect(model.clean.state == .idle)
        #expect(!model.clean.isConfirming)
        #expect(!FileManager.default.fileExists(atPath: directory + "/launched"))
    }

    @Test func onlyTheLatestDiscoveryCanPublishAndClearLoading() async throws {
        let discoveries = Discoveries()
        let model = AppModel(defaults: nil, environment: [:], locator: { await discoveries.locate($0) })
        let first = Task { await model.useCustomCLI(path: "/slow/mo") }
        try await eventually { await discoveries.paths.count == 1 }
        let second = Task { await model.useCustomCLI(path: "/current/mo") }
        try await eventually { await discoveries.paths.count == 2 }
        await discoveries.finish(0, cli: fixtureCLI)
        await first.value
        #expect(model.cli == nil)
        #expect(model.isLocating)
        let current = CLIInfo(executable: "/current/mo", root: "/current", version: "2", installMethod: "test")
        await discoveries.finish(1, cli: current)
        await second.value
        #expect(model.cli == current)
        #expect(!model.isLocating)
    }

    @Test func reloadCanNeverCancelARunningCommand() async throws {
        let model = AppModel(defaults: nil, environment: [:], locator: { _ in sleeperCLI })
        await model.locateCLI()
        model.selection = .clean
        model.clean.requestExternalClean(path: "/Volumes/Fixture", cli: sleeperCLI, preview: false)
        model.clean.confirmExternalClean(cli: sleeperCLI)
        #expect(model.clean.run.isRunning)
        #expect(model.reloadAction == nil)
        #expect(model.cancellationAction != nil)
        model.clean.finishRun()

        model.selection = .history
        #expect(model.reloadAction?.title == "Reload")
        #expect(model.cancellationAction == nil)
        await model.shutdown(lifecycle: ProcessLifecycle())
    }

    @Test func everyCancelIsMarkedSoItCantLandOnReload() async throws {
        let model = AppModel(defaults: nil, environment: [:], locator: { _ in fixtureCLI })
        await model.locateCLI()
        model.selection = .clean
        model.clean.scan(cli: fixtureCLI)
        #expect(model.secondaryAction?.title == "Cancel")
        #expect(model.reloadAction == nil)
        #expect(model.cancellationAction != nil)
        model.cancellationAction?.perform()
        #expect(model.clean.state == .idle)
        await model.shutdown(lifecycle: ProcessLifecycle())
    }

    @Test func lateDiscoveryCannotRestartWorkAfterShutdown() async throws {
        let discoveries = Discoveries()
        let model = AppModel(defaults: nil, environment: [:], locator: { await discoveries.locate($0) })
        let discovery = Task { await model.locateCLI() }
        try await eventually { await discoveries.paths.count == 1 }
        await model.shutdown(lifecycle: ProcessLifecycle())
        await discoveries.finish(0, cli: fixtureCLI)
        await discovery.value
        #expect(model.isShuttingDown)
        #expect(model.cli == nil)
    }

    @Test func monitoringStopsWhenHiddenAndRestartsAtTheVisiblePagesInterval() async throws {
        let root = URL(fileURLWithPath: TestScratch.root).appendingPathComponent("burrow-cli-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        for name in ["status-go", "analyze-go"] { try Data().write(to: root.appendingPathComponent("bin/" + name)) }
        let cli = CLIInfo(executable: "/fixture/mo", root: root.path, version: "1", installMethod: "test")
        let commands = ScriptedCommands()
        let status = StatusStore(commands: commands.client)
        let model = AppModel(defaults: nil, environment: [:], status: status, locator: { _ in cli })
        model.selection = .status
        await model.locateCLI()
        try await eventually { await commands.streams.count == 1 }
        model.setWindowVisible(false)
        #expect(!status.isRunning)
        model.selection = .overview
        await commands.finishStream(0)
        model.setWindowVisible(true)
        try await eventually { await commands.streams.count == 2 }
        #expect(status.isRunning)
        model.setWindowVisible(false)
        await commands.finishStream(1)
        #expect(!status.isRunning)
    }

    @Test func aPromptOnAnotherPageHasAnAttentionDestination() {
        let model = AppModel(defaults: nil, environment: [:])
        model.selection = .overview
        model.clean.run.promptRequest = PromptRequest(prompt: .confirm("Continue?"))
        #expect(model.attentionScreens == [.clean])
        #expect(model.needsAttention(.clean))
        model.selection = .clean
        #expect(model.attentionScreens.isEmpty)
        #expect(model.run(for: .clean) === model.clean.run)
        model.clean.run.promptRequest = nil
        #expect(!model.needsAttention(.clean))
    }

    @Test func analyzeActionsAreNilWithoutBundledTools() async {
        // fixtureCLI has root "/fixture" with no bin/analyze-go, so hasBundledTools == false.
        let model = AppModel(defaults: nil, environment: [:], locator: { _ in fixtureCLI })
        await model.locateCLI()
        #expect(model.cli?.hasBundledTools == false)
        model.selection = .analyze
        #expect(model.secondaryAction == nil)
        #expect(model.primaryAction == nil)
        #expect(model.reloadAction == nil)
    }

    @Test func locateCLIOnLaunchRunsOnlyOnceAcrossReopens() async {
        let counter = OSAllocatedUnfairLock(initialState: 0)
        let model = AppModel(defaults: nil, environment: [:], locator: { _ in
            counter.withLock { $0 += 1 }
            return fixtureCLI
        })
        await model.locateCLIOnLaunch()
        await model.locateCLIOnLaunch()
        #expect(counter.withLock { $0 } == 1)
    }

    @Test func shutdownDisablesPageActionsAndSearchFocusStaysFalseByDefault() async {
        let model = AppModel(defaults: nil, environment: [:], locator: { _ in fixtureCLI })
        await model.locateCLI()
        model.selection = .uninstall
        #expect(!model.isSearchFocused)
        await model.shutdown(lifecycle: ProcessLifecycle())
        #expect(model.isShuttingDown)
        #expect(model.primaryAction == nil)
        #expect(model.secondaryAction == nil)
    }
}
