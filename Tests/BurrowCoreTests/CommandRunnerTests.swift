import Foundation
import Testing
@testable import BurrowCore

struct CommandRunnerTests {
    @Test(arguments: [nil, 60] as [TimeInterval?])
    func completedCommandReleasesItsLifecycleBeforeTheTimeout(timeout: TimeInterval?) async throws {
        var lifecycle: ProcessLifecycle? = ProcessLifecycle()
        let lifecycleWasReleased = { [weak lifecycle] in lifecycle == nil }
        let result = try await CommandRunner.run(
            executable: "/usr/bin/true", arguments: [], timeout: timeout,
            lifecycle: try #require(lifecycle)
        )
        #expect(result.succeeded)
        #expect(lifecycle?.activeProcessCount == 0)
        lifecycle = nil
        // Let the exit callback unwind; the completed command must not wait out its timeout.
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !lifecycleWasReleased(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(lifecycleWasReleased())
    }

    @Test func capturesBothPipesAndExitStatus() async throws {
        let result = try await CommandRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "i=0; while [ $i -lt 2000 ]; do printf 'output\\n'; printf 'error\\n' >&2; i=$((i+1)); done; read line || exit 7"],
            timeout: 5
        )
        #expect(result.status == 7)
        #expect(result.stdout.split(separator: "\n").count == 2000)
        #expect(result.stderr.split(separator: "\n").count == 2000)
    }

    @Test func alreadyCancelledTaskNeverLaunches() async throws {
        let marker = URL(fileURLWithPath: TestScratch.root).appendingPathComponent("burrow-no-launch-" + UUID().uuidString)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CommandRunner.run(executable: "/usr/bin/touch", arguments: [marker.path])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func timeoutEscalatesPastIgnoredTerm() async throws {
        let start = ContinuousClock.now
        await #expect(throws: CommandError.self) {
            try await CommandRunner.run(executable: "/bin/sh", arguments: ["-c", "trap '' TERM; /bin/sleep 4"], timeout: 0.15)
        }
        #expect(start.duration(to: .now) < .seconds(2))
    }

    @Test func cancellationStopsAnUncooperativeProcess() async throws {
        let task = await streamUntilOutput(["-c", "trap '' TERM; printf READY; /bin/sleep 4"])
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(start.duration(to: .now) < .seconds(2))
    }

    @Test func cancellationKillsDescendantsEvenWhenTheParentExitsOnTerm() async throws {
        let marker = URL(fileURLWithPath: TestScratch.root).appendingPathComponent("burrow-child-" + UUID().uuidString)
        let task = await streamUntilOutput(["-c", "(trap '' TERM; printf READY; /bin/sleep 1; /usr/bin/touch \"$1\") & wait", "fixture", marker.path])
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try await Task.sleep(for: .milliseconds(1100))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func missingExecutableFailsWithoutHanging() async {
        await #expect(throws: POSIXError.self) {
            try await CommandRunner.run(executable: "/nonexistent/burrow", arguments: [], timeout: 1)
        }
    }
}
