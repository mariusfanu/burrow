import Foundation
import Darwin
import Testing
@testable import BurrowCore

struct PTYSessionTests {
    @Test(.enabled(if: {
        var limit = rlimit()
        return getrlimit(RLIMIT_NOFILE, &limit) == 0 && limit.rlim_cur > 1200
    }(), "Requires a file descriptor above 1200"))
    func theChildInheritsTheTerminalButNoHighFileDescriptor() async throws {
        let source = open("/dev/null", O_RDONLY)
        try #require(source >= 0)
        defer { close(source) }
        let high = fcntl(source, F_DUPFD, 1200)
        try #require(high >= 1200)
        defer { close(high) }
        let session = try PTYSession(
            executable: "/bin/sh",
            arguments: ["-c", "test -t 0 && test -t 1 && test -t 2 && test ! -e /dev/fd/\(high)"],
            environment: CLILocator.environment()
        )
        #expect(await session.waitForExit() == 0)
    }

    @Test func backpressureDoesNotBlockEchoOrCancellation() async throws {
        let lifecycle = ProcessLifecycle()
        let session = try PTYSession(
            executable: "/bin/sh",
            arguments: ["-c", "trap '' INT TERM; stty -icanon -echo; printf READY; /bin/sleep 4"],
            environment: CLILocator.environment(), lifecycle: lifecycle
        )
        try #require(await terminalReady(session))
        session.write([UInt8](repeating: 0x61, count: 1_000_000))
        let echoStart = ContinuousClock.now
        #expect(session.isEchoEnabled == false)
        #expect(echoStart.duration(to: .now) < .milliseconds(500))
        let cancelStart = ContinuousClock.now
        session.terminate(grace: 0)
        #expect(await session.waitForExit() != 0)
        #expect(cancelStart.duration(to: .now) < .seconds(2))
        #expect(lifecycle.activeProcessCount == 0)
    }

    @Test func cancellationStopsDescendantsAfterTheTerminalRootExits() async throws {
        let lifecycle = ProcessLifecycle()
        let marker = URL(fileURLWithPath: TestScratch.root).appendingPathComponent("burrow-pty-child-" + UUID().uuidString)
        let session = try PTYSession(
            executable: "/bin/sh",
            arguments: ["-c", "(trap '' INT TERM; printf READY; /bin/sleep 1; /usr/bin/touch \"$1\") & wait", "fixture", marker.path],
            environment: CLILocator.environment(), lifecycle: lifecycle
        )
        try #require(await terminalReady(session))
        session.terminate(grace: 0.15)
        #expect(await session.waitForExit() != 0)
        try await Task.sleep(for: .milliseconds(1100))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(lifecycle.activeProcessCount == 0)
    }

    @Test func bufferedInputKeepsOrderAcrossPartialWrites() async throws {
        let lifecycle = ProcessLifecycle()
        let file = URL(fileURLWithPath: TestScratch.root).appendingPathComponent("burrow-pty-input-" + UUID().uuidString)
        let half = 262_144
        let body = #"""
        stty raw -echo
        printf READY
        exec /usr/bin/perl -e '$n=shift; $path=shift; $all=""; while (length($all)<$n) { $r=sysread(STDIN,$part,$n-length($all)); last unless $r; $all.=$part; } open($f,">",$path) or die $!; binmode($f); print $f $all;' "$1" "$2"
        """#
        let session = try PTYSession(
            executable: "/bin/sh", arguments: ["-c", body, "fixture", String(half * 2), file.path],
            environment: CLILocator.environment(), lifecycle: lifecycle
        )
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { session.terminate(grace: 0) }
        }
        defer { watchdog.cancel() }
        try #require(await terminalReady(session))
        session.write([UInt8](repeating: 0x61, count: half))
        session.write([UInt8](repeating: 0x62, count: half))
        #expect(await session.waitForExit() == 0)
        let received = try Data(contentsOf: file)
        #expect(received == Data(repeating: 0x61, count: half) + Data(repeating: 0x62, count: half))
        #expect(lifecycle.activeProcessCount == 0)
    }
}
