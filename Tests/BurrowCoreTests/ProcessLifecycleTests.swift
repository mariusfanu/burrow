import Darwin
import Foundation
import Testing
@testable import BurrowCore

struct ProcessLifecycleTests {
    @Test(arguments: [0, 60] as [TimeInterval])
    func shutdownReleasesATerminalBeforeItsOriginalGraceExpires(grace: TimeInterval) async throws {
        var lifecycle: ProcessLifecycle? = ProcessLifecycle()
        var terminal: PTYSession? = try PTYSession(
            executable: "/bin/sh", arguments: ["-c", "trap '' INT TERM; printf READY; /bin/sleep 4"],
            environment: CLILocator.environment(), lifecycle: try #require(lifecycle)
        )
        let terminalWasReleased = { [weak terminal] in terminal == nil }
        try #require(await terminalReady(try #require(terminal)))
        terminal?.terminate(grace: grace)
        _ = terminal?.isEchoEnabled // The original grace request has reached the queue.
        await lifecycle?.shutdownAll()
        #expect(await terminal?.waitForExit() != 0)
        #expect(lifecycle?.activeProcessCount == 0)
        terminal = nil
        lifecycle = nil
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !terminalWasReleased(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(terminalWasReleased())
    }

    @Test func shutdownReapsPipedAndTerminalCommandsAndClosesAdmission() async throws {
        let lifecycle = ProcessLifecycle()
        let piped = await streamUntilOutput(["-c", "trap '' TERM; printf READY; /bin/sleep 4"], lifecycle: lifecycle)
        let terminal = try PTYSession(
            executable: "/bin/sh", arguments: ["-c", "trap '' INT TERM; printf READY; /bin/sleep 4"],
            environment: CLILocator.environment(), lifecycle: lifecycle
        )
        try #require(await terminalReady(terminal))
        #expect(lifecycle.activeProcessCount == 2)
        let start = ContinuousClock.now
        await lifecycle.shutdownAll()
        #expect(start.duration(to: .now) < .seconds(2))
        #expect(lifecycle.activeProcessCount == 0)
        #expect(await terminal.waitForExit() != 0)
        let probe = kill(terminal.pid, 0)
        let probeError = errno
        #expect(probe == -1)
        #expect(probeError == ESRCH)
        await #expect(throws: CancellationError.self) { try await piped.value }
        await #expect(throws: CancellationError.self) {
            try await CommandRunner.run(executable: "/bin/sleep", arguments: ["4"], lifecycle: lifecycle)
        }
        #expect(throws: CancellationError.self) {
            try PTYSession(executable: "/bin/sleep", arguments: ["4"], environment: [:], lifecycle: lifecycle)
        }
    }

    @Test func shutdownExpeditesATerminalAlreadyWaitingInItsCancellationGrace() async throws {
        let lifecycle = ProcessLifecycle()
        let terminal = try PTYSession(
            executable: "/bin/sh", arguments: ["-c", "trap '' INT TERM; printf READY; /bin/sleep 4"],
            environment: CLILocator.environment(), lifecycle: lifecycle
        )
        try #require(await terminalReady(terminal))
        terminal.terminate(grace: 30)
        _ = terminal.isEchoEnabled // Establish that the queued interrupt request has run.
        let start = ContinuousClock.now
        await lifecycle.shutdownAll()
        #expect(start.duration(to: .now) < .seconds(2))
        #expect(lifecycle.activeProcessCount == 0)
        #expect(await terminal.waitForExit() != 0)
    }

    @Test func shutdownCannotMissConcurrentSpawns() async {
        let lifecycle = ProcessLifecycle()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = try? await CommandRunner.run(
                        executable: "/bin/sleep", arguments: ["4"], timeout: 5, lifecycle: lifecycle
                    )
                }
            }
            await Task.yield()
            await lifecycle.shutdownAll()
        }
        #expect(lifecycle.activeProcessCount == 0)
    }

    @Test func exitNotificationHandlesChildrenThatExitBeforeArming() async throws {
        let lifecycle = ProcessLifecycle()
        for _ in 0..<20 {
            let result = try await CommandRunner.run(executable: "/usr/bin/true", arguments: [], timeout: 10, lifecycle: lifecycle)
            #expect(result.succeeded)
        }
        #expect(lifecycle.activeProcessCount == 0)
    }
}

/// A child that exits while its exit event is still being registered gets no event. Before
/// this was handled, about 1 in 100 quick commands was never noticed to have ended.
@Suite(.timeLimit(.minutes(2)))
struct LostExitTests {
    @Test func noCommandsExitGoesUnnoticed() async {
        let finished = await withTaskGroup(of: Bool.self) { group in
            var finished = 0
            for index in 0..<2_000 {
                if index >= 32, await group.next() == true { finished += 1 }
                group.addTask {
                    (try? await CommandRunner.run(executable: "/usr/bin/true", arguments: [], timeout: 10, lifecycle: ProcessLifecycle())) != nil
                }
            }
            for await result in group where result { finished += 1 }
            return finished
        }
        #expect(finished == 2_000)
    }

    @Test func noTerminalsExitGoesUnnoticed() async throws {
        for _ in 0..<200 {
            let session = try PTYSession(executable: "/usr/bin/true", arguments: [], environment: [:], lifecycle: ProcessLifecycle())
            #expect(await session.waitForExit() == 0)
        }
    }
}

/// A finite fixture will close the stream even if its READY output never arrives.
func terminalReady(_ session: PTYSession) async -> Bool {
    var text = ""
    for await chunk in session.output {
        text += String(decoding: chunk, as: UTF8.self)
        if text.contains("READY") { return true }
    }
    return false
}

/// Starts `/bin/sh` and returns once it has printed something, while it's still running.
func streamUntilOutput(_ arguments: [String], lifecycle: ProcessLifecycle = .shared) async -> Task<Int32, any Error> {
    let (ready, continuation) = AsyncStream<Void>.makeStream()
    let task = Task {
        defer { continuation.finish() }
        return try await CommandRunner.stream(executable: "/bin/sh", arguments: arguments, timeout: 5, lifecycle: lifecycle) { _ in
            continuation.yield(())
        }
    }
    for await _ in ready { break }
    continuation.finish()
    return task
}
