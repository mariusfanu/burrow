import Testing
@testable import Burrow

@MainActor
struct HistoryModelTests {
    @Test func newerHistoryWinsOverLateSuccessAndFailure() async throws {
        let commands = ScriptedCommands()
        let model = HistoryModel(commands: commands.client)
        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 2 }
        await commands.completeRun(1, stdout: "{\"limit\":2}")
        try await eventually { !model.isLoading }
        await commands.completeRun(0, stdout: "{\"limit\":1}")
        for _ in 0..<20 { await Task.yield() }
        #expect(model.report?.limit == 2)
        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 3 }
        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 4 }
        await commands.failRun(2)
        await commands.completeRun(3, stdout: "{\"limit\":4}")
        try await eventually { !model.isLoading }
        #expect(model.report?.limit == 4)
        #expect(model.errorMessage == nil)
    }

    @Test func failedHistoryRetainsDataAndCanRetry() async throws {
        let commands = ScriptedCommands()
        let model = HistoryModel(commands: commands.client)
        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        await commands.completeRun(0, status: 1, stderr: "History is unavailable")
        try await eventually { !model.isLoading }
        #expect(model.report == nil)
        #expect(model.errorMessage == "History is unavailable")
        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 2 }
        await commands.completeRun(1, stdout: "{\"limit\":3}")
        try await eventually { !model.isLoading }
        #expect(model.report?.limit == 3)
        #expect(model.errorMessage == nil)
        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 3 }
        await commands.failRun(2)
        try await eventually { !model.isLoading }
        #expect(model.report?.limit == 3)
        #expect(model.errorMessage != nil)
    }
}
