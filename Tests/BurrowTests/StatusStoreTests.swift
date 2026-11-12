import Foundation
import Observation
import Testing
import BurrowCore
@testable import Burrow

@MainActor
struct StatusStoreTests {
    @Test func aFinalBurstIsAppliedInOrderBeforeRetry() async throws {
        let (store, commands) = started()
        try await eventually { await commands.streams.count == 1 }
        await commands.emit(0, "{\"host\":\"first\"}\n{\"host\":\"last\"}\n")
        await commands.finishStream(0, status: 1)
        try await eventually { await commands.streams.count == 2 }
        #expect(store.snapshot?.host == "last")
        #expect(store.sampleCount == 2)
        #expect(!store.hasFreshSample)
        await commands.emit(1, "{\"host\":\"new attempt\"}\n")
        try await eventually { store.hasFreshSample }
        store.stop()
        await commands.finishStream(1)
    }

    private func started() -> (StatusStore, ScriptedCommands) {
        let commands = ScriptedCommands()
        let store = StatusStore(commands: commands.client, retryDelay: .zero)
        store.start(cli: fixtureCLI, interval: 2)
        return (store, commands)
    }

    @Test func changingCLIAtTheSameIntervalReplacesTheStreamAndRejectsOldOutput() async throws {
        let (store, commands) = started()
        try await eventually { await commands.streams.count == 1 }
        let replacement = CLIInfo(executable: "/other/mo", root: "/other", version: "2", installMethod: "test")
        store.start(cli: replacement, interval: 2)
        try await eventually { await commands.streams.count == 2 }
        #expect(await commands.streams[1].executable == replacement.executable)
        await commands.emit(1, "{\"host\":\"current\"}\n")
        try await eventually { store.snapshot?.host == "current" }
        await commands.emit(0, "{\"host\":\"obsolete\"}\n")
        await commands.finishStream(0)
        // A new current sample provides an observable boundary after the old callbacks.
        await commands.emit(1, "{\"host\":\"still current\"}\n")
        try await eventually { store.snapshot?.host == "still current" }
        #expect(store.isRunning)
        #expect(store.errorMessage == nil)
        store.stop()
        await commands.finishStream(1)
    }

    @Test func aSampleWithoutProcessesKeepsTheLastList() async throws {
        let (store, commands) = started()
        try await eventually { await commands.streams.count == 1 }
        await commands.emit(0, "{\"host\":\"a\",\"top_processes\":[{\"pid\":7,\"name\":\"kept\"}]}\n")
        try await eventually { store.snapshot?.host == "a" }
        await commands.emit(0, "{\"host\":\"b\",\"top_processes\":[]}\n")
        try await eventually { store.snapshot?.host == "b" }
        #expect(store.snapshot?.topProcesses?.map(\.pid) == [7])
        await commands.emit(0, "{\"host\":\"c\",\"top_processes\":[{\"pid\":9,\"name\":\"new\"}]}\n")
        try await eventually { store.snapshot?.host == "c" }
        #expect(store.snapshot?.topProcesses?.map(\.pid) == [9])
        store.stop()
        await commands.finishStream(0)
    }

    @Test func exhaustionClearsTaskAndAllowsAnExplicitSameIntervalRetry() async throws {
        let (store, commands) = started()
        for index in 0..<3 {
            try await eventually { await commands.streams.count == index + 1 }
            await commands.finishStream(index, status: 1)
        }
        try await eventually { !store.isRunning }
        #expect(store.errorMessage != nil)
        store.start(cli: fixtureCLI, interval: 2)
        try await eventually { await commands.streams.count == 4 }
        #expect(store.isRunning)
        store.stop()
        await commands.finishStream(3)
    }

    @Test func aStreamThatWorkedDoesntUseUpItsAttempts() async throws {
        let (store, commands) = started()
        for index in 0..<5 {
            try await eventually { await commands.streams.count == index + 1 }
            await commands.emit(index, "{\"host\":\"sample \(index)\"}\n")
            try await eventually { store.snapshot?.host == "sample \(index)" }
            await commands.finishStream(index, status: 1)
        }
        try await eventually { await commands.streams.count == 6 }
        #expect(store.isRunning)
        store.stop()
        await commands.finishStream(5)
    }

    @Test func outputThatCantBeReadIsReportedUntilASampleArrives() async throws {
        let (store, commands) = started()
        try await eventually { await commands.streams.count == 1 }
        await commands.emit(0, "{\"cpu\":\"not the expected shape\"}\n")
        try await eventually { store.errorMessage?.contains("couldn’t be read") == true }
        await commands.emit(0, "{\"host\":\"readable\"}\n")
        try await eventually { store.snapshot?.host == "readable" }
        #expect(store.errorMessage == nil)
        store.stop()
        await commands.finishStream(0)
    }

    @Test func aMixedChunkDoesNotLeaveAnErrorForTheNextPartialSample() async throws {
        let (store, commands) = started()
        try await eventually { await commands.streams.count == 1 }
        await commands.emit(0, "not json\n{\"host\":\"first\"}\n")
        try await eventually { store.snapshot?.host == "first" }
        #expect(store.errorMessage == nil)

        // Observe the transition too: finishing the next sample would clear a spurious error.
        withObservationTracking {
            _ = store.errorMessage
        } onChange: {
            Issue.record("A valid partial sample must not inherit rejected lines from an earlier chunk")
        }
        await commands.emit(0, "{\"host\":\"sec")
        await commands.emit(0, "ond\"}\n")
        try await eventually { store.snapshot?.host == "second" }
        #expect(store.sampleCount == 2)
        #expect(store.errorMessage == nil)
        store.stop()
        await commands.finishStream(0)
    }

    @Test func gpuUsageTheCLIDoesNotReportComesFromTheSystem() async throws {
        let commands = ScriptedCommands()
        let store = StatusStore(commands: commands.client, retryDelay: .zero) {
            [GPUReading(model: "Apple M3 Pro", utilization: 61)]
        }
        store.start(cli: fixtureCLI, interval: 2)
        try await eventually { await commands.streams.count == 1 }
        await commands.emit(0, "{\"gpu\":[{\"name\":\"Apple M3 Pro\",\"usage\":-1}]}\n")
        try await eventually { store.snapshot != nil }
        #expect(store.snapshot?.gpu?.first?.usage == 61)
        store.stop()
        await commands.finishStream(0)
    }

    @Test func retryStartsWithACleanJSONBuffer() async throws {
        let (store, commands) = started()
        try await eventually { await commands.streams.count == 1 }
        await commands.emit(0, "{\"host\":")
        await commands.finishStream(0, status: 1)
        try await eventually { await commands.streams.count == 2 }
        await commands.emit(1, "{\"host\":\"recovered\"}\n")
        try await eventually { store.snapshot?.host == "recovered" }
        store.stop()
        await commands.finishStream(1)
    }
}
