/// Runs work to its end, and returns early with false if it's still going at the deadline.
@MainActor
func finishes(within deadline: Duration, _ work: @escaping @MainActor () async -> Void) async -> Bool {
    await withCheckedContinuation { continuation in
        var pending: CheckedContinuation<Bool, Never>? = continuation
        @MainActor func finish(_ finished: Bool) {
            pending?.resume(returning: finished)
            pending = nil
        }
        Task {
            await work()
            finish(true)
        }
        Task {
            try? await Task.sleep(for: deadline)
            finish(false)
        }
    }
}
