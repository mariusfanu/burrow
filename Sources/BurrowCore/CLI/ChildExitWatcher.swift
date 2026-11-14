import Foundation
import Synchronization

/// Collects a child that has exited, returning its status as a shell would report it: the exit
/// code, or 128 plus the signal. Returns nil while it's still running.
func reapIfExited(_ pid: pid_t) -> Int32? {
    var status: Int32 = 0
    var reaped: pid_t
    repeat { reaped = waitpid(pid, &status, WNOHANG) } while reaped < 0 && errno == EINTR
    guard reaped == pid || reaped < 0 else { return nil }
    guard reaped == pid else { return 1 }
    let signalNumber = status & 0x7F
    return signalNumber == 0 ? (status >> 8) & 0xFF : 128 + signalNumber
}

/// Tells a child's owner when to look for its exit, on the owner's queue.
///
/// The system's exit event can't be relied on alone. Registering for it finishes some time after
/// `resume`, so a child exiting during that gap gets no event, and a single check right after
/// `resume` can miss it too. About 1 in 100 quick commands went unnoticed that way, so `check`
/// also runs on a timer that backs off quickly, since only that gap depends on it.
final class ChildExitWatcher: @unchecked Sendable {
    private let source: DispatchSourceProcess
    private let queue: DispatchQueue
    private let check: @Sendable () -> Void
    private let isStopped = Mutex(false)

    /// `onEvent` runs when the system reports the exit, and `check` runs on the timer.
    init(pid: pid_t, queue: DispatchQueue, onEvent: @escaping @Sendable () -> Void, check: @escaping @Sendable () -> Void) {
        source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        self.queue = queue
        self.check = check
        source.setEventHandler(handler: onEvent)
        source.resume()
        queue.async(execute: check)
        scheduleCheck(after: 0.05)
    }

    /// Call once the child has been reaped.
    func stop() {
        isStopped.withLock { $0 = true }
        source.cancel()
    }

    private func scheduleCheck(after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !isStopped.withLock({ $0 }) else { return }
            check()
            scheduleCheck(after: min(delay * 2, 2))
        }
    }
}
