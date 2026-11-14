/// Runs work to its end, and returns early with false if it's still going at the deadline.
@MainActor
func finishes(within deadline: Duration, _ work: @escaping @MainActor () async -> Void) async -> Bool {
    await withCheckedContinuation { continuation in
        var pending: CheckedContinuation<Bool, Never>? = continuation
        var timeoutTask: Task<Void, Never>?
        @MainActor func finish(_ finished: Bool) {
            timeoutTask?.cancel()
            timeoutTask = nil
            pending?.resume(returning: finished)
            pending = nil
        }
        timeoutTask = Task {
            try? await Task.sleep(for: deadline)
            guard !Task.isCancelled else { return }
            finish(false)
        }
        Task {
            await work()
            finish(true)
        }
    }
}
