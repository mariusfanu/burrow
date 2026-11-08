import CPTY
import Darwin
import Foundation

public struct CommandResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { status == 0 }

    /// Throws the command's stderr, without its escape codes, if it failed.
    public func requireSuccess() throws {
        guard succeeded else {
            throw CommandError.failed(status: status, message: ANSI.strip(stderr))
        }
    }
}

public enum CommandError: Error, LocalizedError {
    case timedOut
    case failed(status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .timedOut:
            "The command took too long and was stopped."
        case .failed(let status, let message):
            message.isEmpty ? "The command exited with status \(status)." : message
        }
    }
}

/// Runs commands without a terminal, for read-only work such as JSON and previews.
public enum CommandRunner {
    /// Runs a command to completion. Cancelling the calling task terminates it.
    public static func run(
        executable: String,
        arguments: [String],
        environment: [String: String] = CLILocator.environment(),
        timeout: TimeInterval? = nil,
        lifecycle: ProcessLifecycle = .shared
    ) async throws -> CommandResult {
        let out = OutputBuffer()
        let err = OutputBuffer()
        let status = try await stream(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: timeout,
            lifecycle: lifecycle,
            onStdout: { out.append($0) },
            onStderr: { err.append($0) }
        )
        return CommandResult(status: status, stdout: out.text, stderr: err.text)
    }

    /// Runs a command, handing output chunks over as they arrive.
    public static func stream(
        executable: String,
        arguments: [String],
        environment: [String: String] = CLILocator.environment(),
        timeout: TimeInterval? = nil,
        lifecycle: ProcessLifecycle = .shared,
        onStdout: @escaping @Sendable (Data) -> Void,
        onStderr: @escaping @Sendable (Data) -> Void = { _ in }
    ) async throws -> Int32 {
        try Task.checkCancellation()
        let outPipe = Pipe()
        let errPipe = Pipe()
        let box = ProcessBox(lifecycle: lifecycle)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                let drainGroup = DispatchGroup()
                drain(outPipe, group: drainGroup, into: onStdout)
                drain(errPipe, group: drainGroup, into: onStderr)

                do {
                    try box.start(executable: executable, arguments: arguments, environment: environment,
                                  output: outPipe.fileHandleForWriting.fileDescriptor,
                                  error: errPipe.fileHandleForWriting.fileDescriptor)
                    // The child owns its duplicated writers; EOF must not depend on the parent.
                    try? outPipe.fileHandleForWriting.close()
                    try? errPipe.fileHandleForWriting.close()
                } catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    try? outPipe.fileHandleForWriting.close()
                    try? errPipe.fileHandleForWriting.close()
                    continuation.resume(throwing: error)
                    return
                }

                box.wait { status, reason in
                    // A detached helper may hold a pipe open. Bound the final drain too.
                    _ = drainGroup.wait(timeout: .now() + 1)
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    switch reason {
                    case .timedOut: continuation.resume(throwing: CommandError.timedOut)
                    case .cancelled: continuation.resume(throwing: CancellationError())
                    case nil: continuation.resume(returning: status)
                    }
                }

                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak box] in
                        box?.stop(reason: .timedOut)
                    }
                }
            }
        } onCancel: {
            box.stop(reason: .cancelled)
        }
    }

    /// Hands a pipe's chunks to `handler`, staying in `group` until it reaches EOF.
    private static func drain(_ pipe: Pipe, group: DispatchGroup, into handler: @escaping @Sendable (Data) -> Void) {
        group.enter()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                group.leave()
            } else {
                handler(data)
            }
        }
    }
}

/// Owns a process group from spawn through reap. Startup and cancellation share a lock.
private final class ProcessBox: @unchecked Sendable {
    enum StopReason: Sendable { case cancelled, timedOut }
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "burrow.command.wait")
    private let lifecycle: ProcessLifecycle
    private var registration: ProcessRegistration?
    private var pid: pid_t?
    private var reason: StopReason?
    private var isEscalating = false
    private var finished = false
    private var exitResult: (Int32, StopReason?)?
    private var exitWatcher: ChildExitWatcher?
    private var completion: (@Sendable (Int32, StopReason?) -> Void)?

    init(lifecycle: ProcessLifecycle) { self.lifecycle = lifecycle }

    func start(executable: String, arguments: [String], environment: [String: String], output: Int32, error: Int32) throws {
        let registration = try lifecycle.register()
        do {
            let input = open("/dev/null", O_RDONLY | O_CLOEXEC)
            guard input >= 0 else { throw POSIXError(.EBADF) }
            defer { close(input) }
            var argv = ([executable] + arguments).map { strdup($0) }
            argv.append(nil)
            var envp = environment.map { strdup("\($0.key)=\($0.value)") }
            envp.append(nil)
            defer {
                argv.forEach { free($0) }
                envp.forEach { free($0) }
            }
            try lock.withLock {
                guard reason == nil, !registration.isStopRequested else { throw CancellationError() }
                var child: pid_t = 0
                let result = cpipe_spawn(executable, argv, envp, input, output, error, &child)
                guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
                pid = child
                self.registration = registration
            }
            registration.installStop { [self] in stop(reason: .cancelled) }
        } catch {
            registration.finish()
            throw error
        }
    }

    func stop(reason requested: StopReason) {
        let child = lock.withLock { () -> pid_t? in
            guard !finished, reason == nil else { return nil }
            reason = requested
            guard let pid else { return nil }
            isEscalating = true
            // Serialize the signal with reap, so an exited PID cannot be reused here.
            killpg(pid, SIGTERM)
            return pid
        }
        guard child != nil else { return }
        queue.asyncAfter(deadline: .now() + 0.25) { [self] in
            lock.withLock {
                guard !finished, let pid else { return }
                // The root stays unreaped until this group-wide escalation has happened.
                killpg(pid, SIGKILL)
                isEscalating = false
            }
            reapIfReady()
        }
    }

    func wait(onExit: @escaping @Sendable (Int32, StopReason?) -> Void) {
        queue.async { [self] in
            let completed = lock.withLock { () -> (Int32, StopReason?)? in
                if let exitResult { return exitResult }
                completion = onExit
                return nil
            }
            if let (status, reason) = completed {
                onExit(status, reason)
                return
            }
            guard let child = lock.withLock({ pid }) else { return }
            let check: @Sendable () -> Void = { [weak self] in self?.reapIfReady() }
            let watcher = ChildExitWatcher(pid: child, queue: queue, onEvent: check, check: check)
            lock.withLock { exitWatcher = watcher }
        }
    }

    private func reapIfReady() {
        let result = lock.withLock { () -> (Int32, StopReason?, ProcessRegistration?, (@Sendable (Int32, StopReason?) -> Void)?)? in
            guard let pid, !finished, !isEscalating else { return nil }
            guard let code = reapIfExited(pid) else { return nil }
            finished = true
            exitWatcher?.stop()
            exitWatcher = nil
            let callback = completion
            completion = nil
            let ownedRegistration = registration
            registration = nil
            exitResult = (code, reason)
            return (code, reason, ownedRegistration, callback)
        }
        if let (status, reason, registration, callback) = result {
            registration?.finish()
            callback?(status, reason)
        }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.withLock { data.append(chunk) }
    }

    var text: String {
        lock.withLock { String(decoding: data, as: UTF8.self) }
    }
}
