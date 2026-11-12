import Foundation

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
