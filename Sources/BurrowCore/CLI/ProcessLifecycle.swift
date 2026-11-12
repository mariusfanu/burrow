import Foundation

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

    func finish(_ id: UUID) {
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
