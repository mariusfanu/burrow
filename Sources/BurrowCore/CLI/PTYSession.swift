import CPTY
import Darwin
import Foundation

public enum PTYError: Error, LocalizedError {
    case spawnFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .spawnFailed(let code):
            "Could not start the command: \(String(cString: strerror(code)))"
        }
    }
}

/// Closes the terminal only once the sources watching it are done with it, as libdispatch
/// requires, so that the number can't be reused while one is still being torn down.
/// Used only on the session's queue.
private final class MasterDescriptor: @unchecked Sendable {
    let fd: Int32
    private var activeSources = 0
    private var closeRequested = false
    private var isClosed = false

    init(fd: Int32) { self.fd = fd }

    func sourceStarted() { activeSources += 1 }

    func sourceEnded() {
        activeSources -= 1
        closeIfUnused()
    }

    func requestClose() {
        closeRequested = true
        closeIfUnused()
    }

    private func closeIfUnused() {
        guard closeRequested, activeSources == 0, !isClosed else { return }
        isClosed = true
        close(fd)
    }
}

/// A child process attached to a pseudo-terminal. All descriptor state is serialized
/// on a queue, whose reads and writes are nonblocking so input backpressure cannot
/// delay echo checks, resize requests or cancellation escalation.
public final class PTYSession: @unchecked Sendable {
    /// The command's output. Reading stops while too much of it waits to be consumed, so a
    /// fast command waits for the app rather than filling memory.
    public struct Output: AsyncSequence, Sendable {
        public typealias Element = Data
        let stream: AsyncStream<Data>
        let session: PTYSession

        public func makeAsyncIterator() -> Iterator {
            Iterator(base: stream.makeAsyncIterator(), session: session)
        }

        /// Asking for the next chunk is what says the last one has been dealt with.
        public struct Iterator: AsyncIteratorProtocol {
            var base: AsyncStream<Data>.Iterator
            let session: PTYSession
            var unacknowledged = 0

            public mutating func next() async -> Data? {
                acknowledge()
                let chunk = await base.next()
                unacknowledged = chunk?.count ?? 0
                return chunk
            }

            public mutating func next(isolation actor: isolated (any Actor)?) async -> Data? {
                acknowledge()
                let chunk = await base.next(isolation: actor)
                unacknowledged = chunk?.count ?? 0
                return chunk
            }

            private mutating func acknowledge() {
                if unacknowledged > 0 { session.acknowledge(unacknowledged) }
                unacknowledged = 0
            }
        }
    }

    public let pid: pid_t
    public var output: Output { Output(stream: outputStream, session: self) }

    private let outputStream: AsyncStream<Data>
    private let master: Int32
    private let descriptor: MasterDescriptor
    private let highWaterMark: Int
    private let lowWaterMark: Int
    private var bufferedBytes = 0
    private var isReadSuspended = false
    private let registration: ProcessRegistration
    private let queue = DispatchQueue(label: "burrow.pty")
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var exitWatcher: ChildExitWatcher?
    private var continuation: AsyncStream<Data>.Continuation?
    private var exitStatus: Int32?
    private var exitWaiters: [CheckedContinuation<Int32, Never>] = []
    private var masterClosed = false
    private var pendingInput = Data()
    private var inputOffset = 0
    private enum TerminationPhase { case none, interrupt, terminate, killed }
    private var terminationPhase = TerminationPhase.none

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        rows: UInt16 = 40,
        columns: UInt16 = 120,
        lifecycle: ProcessLifecycle = .shared,
        highWaterMark: Int = 1 << 20
    ) throws {
        let registration = try lifecycle.register()
        var initialized = false
        defer { if !initialized { registration.finish() } }
        guard !registration.isStopRequested else { throw CancellationError() }
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var masterFD: Int32 = -1
        var childPID: pid_t = 0
        let result = cpty_spawn(executable, argv, envp, rows, columns, &masterFD, &childPID)
        guard result == 0 else { throw PTYError.spawnFailed(result) }
        let flags = fcntl(masterFD, F_GETFL)
        guard flags >= 0, fcntl(masterFD, F_SETFL, flags | O_NONBLOCK) == 0 else {
            let failure = errno
            killpg(childPID, SIGKILL)
            close(masterFD)
            var status: Int32 = 0
            while waitpid(childPID, &status, 0) < 0, errno == EINTR {}
            throw PTYError.spawnFailed(failure)
        }

        master = masterFD
        descriptor = MasterDescriptor(fd: masterFD)
        self.highWaterMark = highWaterMark
        lowWaterMark = highWaterMark / 4
        pid = childPID
        self.registration = registration

        let (output, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
        outputStream = output
        self.continuation = continuation
        initialized = true
        registration.installStop { [self] in requestTermination(grace: 0.15, expediteExisting: true) }
        startReading()
        watchForExit()
    }

    deinit {
        resumeReadingIfSuspended()
        readSource?.cancel()
        writeSource?.cancel()
        let descriptor = descriptor
        queue.async { descriptor.requestClose() }
    }

    /// Enqueues input in order. A full terminal input buffer yields to its write
    /// source instead of blocking the queue that services echo and cancellation.
    public func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        queue.async { [self] in
            guard !masterClosed, exitStatus == nil, terminationPhase == .none else { return }
            if inputOffset > 0 {
                pendingInput.removeSubrange(..<inputOffset)
                inputOffset = 0
            }
            pendingInput.append(contentsOf: bytes)
            flushInput()
        }
    }

    public func write(_ text: String) { write(Array(text.utf8)) }

    private func flushInput() {
        guard !masterClosed else { return }
        // Bound one dispatch turn even if a reader continuously accepts input.
        var sent = 0
        var attempts = 0
        while inputOffset < pendingInput.count, sent < 65_536, attempts < 16 {
            attempts += 1
            let amount = min(pendingInput.count - inputOffset, 65_536 - sent)
            let written = pendingInput.withUnsafeBytes {
                Darwin.write(master, $0.baseAddress!.advanced(by: inputOffset), amount)
            }
            if written > 0 {
                inputOffset += written
                sent += written
            } else if written < 0, errno == EINTR {
                continue
            } else if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                ensureWriteSource()
                return
            } else {
                discardInput()
                return
            }
        }
        if inputOffset == pendingInput.count {
            discardInput()
        } else {
            ensureWriteSource()
        }
    }

    private func ensureWriteSource() {
        guard writeSource == nil, !masterClosed else { return }
        let source = DispatchSource.makeWriteSource(fileDescriptor: master, queue: queue)
        source.setEventHandler { [weak self] in self?.flushInput() }
        descriptor.sourceStarted()
        source.setCancelHandler { [descriptor] in descriptor.sourceEnded() }
        writeSource = source
        source.resume()
    }

    private func discardInput() {
        writeSource?.cancel()
        writeSource = nil
        pendingInput.removeAll(keepingCapacity: false)
        inputOffset = 0
    }

    public func resize(rows: UInt16, columns: UInt16) {
        queue.async { [self] in
            guard !masterClosed else { return }
            _ = cpty_resize(master, rows, columns)
        }
    }

    /// Unknown or closed terminal state counts as nil. The queue never waits for
    /// terminal input to drain, so a main-actor password check stays responsive.
    public var isEchoEnabled: Bool? {
        queue.sync {
            guard !masterClosed else { return nil }
            var attributes = termios()
            guard tcgetattr(master, &attributes) == 0 else { return nil }
            return attributes.c_lflag & tcflag_t(ECHO) != 0
        }
    }

    /// Stops the command as Control-C does. The terminal delivers that itself, which also
    /// reaches a root-owned `sudo` in the foreground, where `killpg` isn't permitted to. A
    /// shell can't run its handler until that child has ended, so this is what makes a
    /// cancelled administrator step stop straight away.
    private func interruptForeground() {
        var attributes = termios()
        if !masterClosed, tcgetattr(master, &attributes) == 0, attributes.c_lflag & tcflag_t(ISIG) != 0,
           tcgetpgrp(master) == pid {
            var character = withUnsafeBytes(of: attributes.c_cc) { $0[Int(VINTR)] }
            if character != 0xFF, Darwin.write(master, &character, 1) == 1 { return }
        }
        sendSignal(SIGINT)
    }

    private func sendSignal(_ signal: Int32) {
        // forkpty makes the child a session leader, so its pid is its group id.
        if killpg(pid, signal) != 0 { kill(pid, signal) }
    }

    /// Asks the command to stop as Ctrl-C would. If the root exits first, stop its
    /// remaining group before reap; otherwise escalate after the cleanup grace.
    public func terminate(grace: TimeInterval = 4) {
        requestTermination(grace: grace, expediteExisting: false)
    }

    private func requestTermination(grace: TimeInterval, expediteExisting: Bool) {
        queue.async { [self] in
            guard exitStatus == nil else { return }
            if terminationPhase == .interrupt, expediteExisting {
                beginTerminatingGroup()
                return
            }
            guard terminationPhase == .none else { return }
            discardInput()
            terminationPhase = .interrupt
            interruptForeground()
            queue.asyncAfter(deadline: .now() + max(grace, 0)) { [weak self] in
                guard let self, exitStatus == nil, terminationPhase == .interrupt else { return }
                beginTerminatingGroup()
            }
        }
    }

    private func beginTerminatingGroup() {
        terminationPhase = .terminate
        sendSignal(SIGTERM)
        queue.asyncAfter(deadline: .now() + 0.25) { [self] in
            guard exitStatus == nil, terminationPhase == .terminate else { return }
            sendSignal(SIGKILL)
            terminationPhase = .killed
            reap()
        }
    }

    public func waitForExit() async -> Int32 {
        await withCheckedContinuation { waiter in
            queue.async { [self] in
                if let exitStatus { waiter.resume(returning: exitStatus) }
                else { exitWaiters.append(waiter) }
            }
        }
    }

    private func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        descriptor.sourceStarted()
        source.setCancelHandler { [descriptor] in descriptor.sourceEnded() }
        readSource = source
        source.resume()
    }

    private func drain() {
        guard !masterClosed else { return }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let count = buffer.withUnsafeMutableBytes { Darwin.read(master, $0.baseAddress, $0.count) }
        if count > 0 {
            bufferedBytes += count
            continuation?.yield(Data(buffer[0..<count]))
            if bufferedBytes >= highWaterMark, !isReadSuspended, let readSource {
                isReadSuspended = true
                readSource.suspend()
            }
        } else if count == 0 || (errno != EAGAIN && errno != EINTR) { finishStream() }
    }

    fileprivate func acknowledge(_ count: Int) {
        queue.async { [self] in
            bufferedBytes -= count
            if bufferedBytes <= lowWaterMark { resumeReadingIfSuspended() }
        }
    }

    private func resumeReadingIfSuspended() {
        guard isReadSuspended else { return }
        isReadSuspended = false
        readSource?.resume()
    }

    /// For checking backpressure in tests.
    func bufferedByteCount() -> Int { queue.sync { bufferedBytes } }

    private func watchForExit() {
        queue.async { [self] in
            exitWatcher = ChildExitWatcher(
                pid: pid,
                queue: queue,
                onEvent: { [weak self] in
                    guard let self else { return }
                    // The root has exited during a cancel, so the rest of its group goes next.
                    if terminationPhase == .interrupt { beginTerminatingGroup() } else { reap() }
                },
                check: { [weak self] in self?.reap() }
            )
        }
    }

    private func reap() {
        guard exitStatus == nil,
              terminationPhase == .none || terminationPhase == .killed else { return }
        if let status = reapIfExited(pid) { recordExit(status) }
    }

    private func recordExit(_ status: Int32) {
        exitStatus = status
        discardInput()
        exitWatcher?.stop()
        exitWatcher = nil
        registration.finish()
        exitWaiters.forEach { $0.resume(returning: status) }
        exitWaiters.removeAll()
        finishAfterDraining(graceServed: false, attemptsLeft: 50)
    }

    /// A helper can hold the terminal open after the command exits, so reading stops after a
    /// short grace. A slow consumer holding reads back gets time to catch up first.
    private func finishAfterDraining(graceServed: Bool, attemptsLeft: Int) {
        guard continuation != nil else { return }
        if isReadSuspended, attemptsLeft > 0 {
            queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.finishAfterDraining(graceServed: graceServed, attemptsLeft: attemptsLeft - 1)
            }
        } else if graceServed {
            finishStream()
        } else {
            queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.finishAfterDraining(graceServed: true, attemptsLeft: attemptsLeft)
            }
        }
    }

    private func finishStream() {
        // A suspended source never reports its cancellation.
        resumeReadingIfSuspended()
        readSource?.cancel()
        readSource = nil
        discardInput()
        continuation?.finish()
        continuation = nil
        closeMaster()
    }

    private func closeMaster() {
        guard !masterClosed else { return }
        masterClosed = true
        descriptor.requestClose()
    }
}
