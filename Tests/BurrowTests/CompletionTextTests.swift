import Testing
@testable import Burrow

@MainActor
struct CompletionTextTests {
    @Test func successUsesTheRequestedTitleAndDuration() async throws {
        let run = RunController(policy: .live)
        run.start(title: "Test", doneTitle: "All Clean", cli: shellCLI, arguments: ["-c", "exit 0"])
        try await eventually { !run.isRunning }
        #expect(run.didSucceed)
        #expect(run.completionHeadline == "All Clean")
        #expect(run.completionSymbol == "checkmark.circle")
        #expect(run.completionDetail.hasPrefix("Finished in "))
    }

    @Test func failureReportsTheExitStatus() async throws {
        let run = RunController(policy: .live)
        run.start(title: "Test", cli: shellCLI, arguments: ["-c", "exit 3"])
        try await eventually { !run.isRunning }
        #expect(run.completionHeadline == "Couldn’t Finish")
        #expect(run.completionSymbol == "xmark.circle")
        #expect(run.completionDetail == "The command ended with status 3. The log has the details.")
    }

    @Test func cancellationUsesTheStoppedMessage() async throws {
        let run = RunController(policy: .live)
        run.start(title: "Test", cli: shellCLI, arguments: ["-c", "exec /bin/sleep 10"])
        defer { run.cancel() }
        try #require(run.isRunning)
        run.cancel()
        try await eventually { !run.isRunning }
        #expect(run.completionHeadline == "Stopped")
        #expect(run.completionSymbol == "stop.circle")
        #expect(run.completionDetail == "Anything already finished stays finished.")
    }
}
