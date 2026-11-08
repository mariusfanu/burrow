import Foundation

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
    private var isStopped = false

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

    /// Call on the owner's queue once the child has been reaped.
    func stop() {
        isStopped = true
        source.cancel()
    }

    private func scheduleCheck(after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !isStopped else { return }
            check()
            scheduleCheck(after: min(delay * 2, 2))
        }
    }
}

/// Owns child processes for the lifetime of an app (or an isolated test session).
/// Shutdown closes admission before requesting cancellation, then waits for every
/// registered child to be reaped. Registrations also cover a spawn racing with quit.
public final class ProcessLifecycle: @unchecked Sendable {
    public static let shared = ProcessLifecycle()

    private let lock = NSLock()
    private var registrations: [UUID: ProcessRegistration] = [:]
    private var isShuttingDown = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public var activeProcessCount: Int { lock.withLock { registrations.count } }

    public func shutdownAll() async {
        let active = lock.withLock {
            isShuttingDown = true
            return Array(registrations.values)
        }
        active.forEach { $0.requestStop() }
        await withCheckedContinuation { waiter in
            let complete = lock.withLock {
                if registrations.isEmpty { return true }
                waiters.append(waiter)
                return false
            }
            if complete { waiter.resume() }
        }
    }

    func register() throws -> ProcessRegistration {
        try lock.withLock {
            guard !isShuttingDown else { throw CancellationError() }
            let registration = ProcessRegistration(lifecycle: self)
            registrations[registration.id] = registration
            return registration
        }
    }

    fileprivate func finish(_ id: UUID) {
        let completed = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            registrations.removeValue(forKey: id)
            guard registrations.isEmpty else { return [] }
            let completed = waiters
            waiters = []
            return completed
        }
        completed.forEach { $0.resume() }
    }
}

/// Installed before spawning, so shutdown cannot miss a child whose initialization
/// is in flight. The stop closure retains its process owner until exit, then clears.
final class ProcessRegistration: @unchecked Sendable {
    let id = UUID()
    private weak var lifecycle: ProcessLifecycle?
    private let lock = NSLock()
    private var stop: (@Sendable () -> Void)?
    private var stopRequested = false
    private var finished = false

    init(lifecycle: ProcessLifecycle) { self.lifecycle = lifecycle }

    var isStopRequested: Bool { lock.withLock { stopRequested } }

    func installStop(_ stop: @escaping @Sendable () -> Void) {
        let shouldStop = lock.withLock {
            guard !finished else { return false }
            self.stop = stop
            return stopRequested
        }
        if shouldStop { stop() }
    }

    func requestStop() {
        let callback = lock.withLock {
            stopRequested = true
            return stop
        }
        callback?()
    }

    func finish() {
        let shouldFinish = lock.withLock {
            guard !finished else { return false }
            finished = true
            stop = nil
            return true
        }
        if shouldFinish { lifecycle?.finish(id) }
    }
}
