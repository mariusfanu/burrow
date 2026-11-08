import Foundation
import Testing
@testable import Burrow

@MainActor
struct ScanOwnershipTests {
    @Test func cancelledCleanScanCannotResetOrPublishIntoItsReplacement() async throws {
        let commands = ScriptedCommands()
        let model = CleanModel(commands: commands.client, policy: .live)
        model.scan(cli: fixtureCLI)
        try await eventually { await commands.streams.count == 1 }
        model.cancelScan()
        model.scan(cli: fixtureCLI)
        try await eventually { await commands.streams.count == 2 }
        await commands.emit(0, "➤ Obsolete section\n  ○ Old data · 1GB\n")
        await commands.finishStream(0)
        // Deliver a current callback after the obsolete completion has had a turn.
        await commands.emit(1, "➤ Current section\n  ○ New data · 2GB\n")
        try await eventually { model.report.sections.first?.name == "Current section" }
        #expect(model.state == .scanning)
        #expect(model.errorMessage == nil)
        await commands.finishStream(1)
        try await eventually { model.state == .review }
        #expect(model.report.sections.map(\.name) == ["Current section"])
    }

    @Test func cancelledOptimizePreviewCannotResetOrPublishIntoItsReplacement() async throws {
        let commands = ScriptedCommands()
        let model = OptimizeModel(commands: commands.client, policy: .live)
        model.preview(cli: fixtureCLI)
        try await eventually { await commands.streams.count == 1 }
        model.cancelPreview()
        model.preview(cli: fixtureCLI)
        try await eventually { await commands.streams.count == 2 }
        await commands.finishStream(0)
        await commands.emit(0, "➤ Obsolete work\n")
        await commands.emit(1, "➤ Current work\n")
        try await eventually { model.activity == "Current work" }
        #expect(model.state == .previewing)
        await commands.finishStream(1)
        try await eventually { model.state == .review }
        #expect(model.lines.map(\.title) == ["Current work"])
    }

    @Test(arguments: [false, true])
    func optimizeKeepsResultsOnlyWhenTheFailedPreviewFinished(completed: Bool) async throws {
        let commands = ScriptedCommands()
        let model = OptimizeModel(commands: commands.client, policy: .live)
        model.preview(cli: fixtureCLI)
        try await eventually { await commands.streams.count == 1 }
        await commands.emit(0, "➤ Spotlight Orphan Rules\n  ◎ Failed to inspect Spotlight search rules\n")
        if completed {
            await commands.emit(0, "Dry Run Complete, No Changes Made\n1 failed\n")
        }
        await commands.finishStream(0, status: 1)
        try await eventually { model.state != .previewing }

        #expect(model.state == (completed ? .review : .idle))
        #expect(model.lines.contains { $0.title == "Spotlight Orphan Rules" } == completed)
        #expect(model.errorMessage != nil)
        model.runMaintenance(cli: fixtureCLI, preview: false)
        #expect(!model.run.isRunning)
        #expect(model.state != .running)
    }
}
