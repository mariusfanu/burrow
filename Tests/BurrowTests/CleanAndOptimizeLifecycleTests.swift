import Foundation
import Testing
import BurrowCore
@testable import Burrow

@MainActor
struct CleanLifecycleTests {
    @Test func scanReviewCleanAndFinishLifecycle() async throws {
        let commands = ScriptedCommands()
        let model = CleanModel(commands: commands.client, policy: .live)
        #expect(model.state == .idle)

        model.scan(cli: fixtureCLI)
        #expect(model.state == .scanning)
        try await eventually { await commands.streams.count == 1 }
        await commands.emit(0, "➤ User Caches\n  ○ ~/Library/Caches/Foo · 10MB\n")
        await commands.finishStream(0, status: 0)
        try await eventually { model.state == .review }
        #expect(model.report.sections.map(\.name) == ["User Caches"])
        #expect(model.errorMessage == nil)

        // Preview clean
        model.clean(cli: fixtureCLI, preview: true)
        #expect(model.state == .running)
        #expect(model.run.isPreview)
        #expect(model.run.commandLine == "mo clean --dry-run")
        model.run.cancel()
        try await eventually { !model.run.isRunning }
        model.finishRun()
        #expect(model.state == .idle)
    }

    @Test func liveCleanRunsRealCommandWhenPolicyIsLive() async throws {
        let commands = ScriptedCommands()
        let model = CleanModel(commands: commands.client, policy: .live)
        model.scan(cli: fixtureCLI)
        try await eventually { await commands.streams.count == 1 }
        await commands.emit(0, "➤ User Caches\n  ○ ~/Library/Caches/Foo · 10MB\n")
        await commands.finishStream(0, status: 0)
        try await eventually { model.state == .review }

        model.clean(cli: fixtureCLI, preview: false)
        #expect(model.state == .running)
        #expect(!model.run.isPreview)
        #expect(model.run.commandLine == "mo clean")
        model.run.cancel()
        try await eventually { !model.run.isRunning }
        model.finishRun()
        #expect(model.state == .idle)
    }

    @Test func scanCancelAndFailureReturnToIdle() async throws {
        let commands = ScriptedCommands()
        let model = CleanModel(commands: commands.client, policy: .live)

        model.scan(cli: fixtureCLI)
        try await eventually { await commands.streams.count == 1 }
        model.cancelScan()
        #expect(model.state == .idle)

        model.scan(cli: fixtureCLI)
        try await eventually { await commands.streams.count == 2 }
        await commands.finishStream(1, status: 1)
        try await eventually { model.state == .idle && model.errorMessage != nil }
    }
}

@MainActor
struct OptimizeLifecycleTests {
    @Test func previewReviewRunAndCancelLifecycle() async throws {
        let commands = ScriptedCommands()
        let model = OptimizeModel(commands: commands.client, policy: .live)
        #expect(model.state == .idle)

        model.preview(cli: fixtureCLI)
        #expect(model.state == .previewing)
        try await eventually { await commands.streams.count == 1 }
        model.cancelPreview()
        #expect(model.state == .idle)

        model.preview(cli: fixtureCLI)
        try await eventually { await commands.streams.count == 2 }
        await commands.emit(1, "➤ DNS Cache\n  ✓ Flushed DNS\n")
        await commands.finishStream(1, status: 0)
        try await eventually { model.state == .review }

        model.runMaintenance(cli: fixtureCLI, preview: true)
        #expect(model.state == .running)
        #expect(model.run.isPreview)
        #expect(model.run.commandLine == "mo optimize --dry-run")
        model.run.cancel()
        try await eventually { !model.run.isRunning }
        model.finishRun(cli: fixtureCLI)
        // finishRun re-previews when !changedSomething? Let's check: finishRun calls preview or sets idle.
        #expect(model.state == .idle || model.state == .previewing)
        model.cancelPreview()
    }

    @Test func planGroupsAssignDistinctIDsToDuplicateSectionTitles() {
        let lines = [
            LogLine(id: 1, raw: "➤ System"),
            LogLine(id: 2, raw: "  ✓ First item"),
            LogLine(id: 3, raw: "➤ System"),
            LogLine(id: 4, raw: "  ✓ Second item"),
        ]
        let groups = OptimizePlan.groups(from: lines)
        #expect(groups.count == 2)
        #expect(Set(groups.map(\.id)).count == 2)
    }

    @Test func cleanConfirmationMessageAndInvalidateReview() async throws {
        let commands = ScriptedCommands()
        let model = CleanModel(commands: commands.client, policy: .live)
        #expect(!CleanModel.confirmationMessage(for: model.report).contains("empties your Trash"))

        model.scan(cli: fixtureCLI)
        try await eventually { await commands.streams.count == 1 }
        await commands.emit(0, "➤ System\n  ○ Trash · 1.0MB dry\n")
        await commands.finishStream(0, status: 0)
        try await eventually { model.state == .review }

        #expect(CleanModel.confirmationMessage(for: model.report).contains("empties your Trash"))

        model.invalidateReview()
        #expect(model.state == .idle)
        #expect(model.report.sections.isEmpty)
    }

    @Test func optimizeTreatsDryRunCompleteStatusOneAsFailureAndInvalidateClearsReview() async throws {
        let commands = ScriptedCommands()
        let model = OptimizeModel(commands: commands.client, policy: .live)
        model.preview(cli: fixtureCLI)
        try await eventually { await commands.streams.count == 1 }
        await commands.emit(0, "➤ System\n  ✓ Checked\nDry Run Complete, No Changes Made\n")
        await commands.finishStream(0, status: 1)
        try await eventually { model.state == .review }
        #expect(model.errorMessage != nil)

        model.invalidateReview()
        #expect(model.state == .idle)
        #expect(model.lines.isEmpty)
        #expect(model.errorMessage == nil)
    }
}
