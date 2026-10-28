/// One mutation at a time per scope. The CLI has no lock of its own, so two `add`s in one project would race on
/// skills.lock; mutations of different scopes and every read-only command run in parallel. Actors are reentrant at
/// each `await`, so the order is kept by chaining explicit tail tasks, not by the actor alone.
public actor MutationQueue {
    private var tails: [Scope: Task<Void, Never>] = [:]
    private var busy: [Scope: Int] = [:]

    public init() {}

    /// Runs `operation` after every mutation queued earlier for `scope`. Cancelling the caller cancels this
    /// operation (and through the runner, its child) but not the ones queued behind it. A caller cancelled before
    /// its operation starts never runs it.
    public func enqueue<T: Sendable>(
        in scope: Scope, _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        // Cancelled before it got here: no slot, and nothing for later mutations to wait on.
        try Task.checkCancellation()
        let previous = tails[scope]
        busy[scope, default: 0] += 1
        defer { finished(scope) }
        // `task` is unstructured, so it learns of the caller's cancellation only through the handler below; `start`
        // keeps it from checking before that handler is installed.
        let task = Task<T, any Error> { try await self.start(after: previous, operation) }
        tails[scope] = Task { _ = try? await task.value }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Whether a mutation is running or waiting for `scope`; the UI disables the mutating actions of that scope.
    public func isBusy(_ scope: Scope) -> Bool {
        busy[scope, default: 0] > 0
    }

    /// How many mutations of `scope` are running or waiting (tests: a second one has queued).
    func pending(in scope: Scope) -> Int {
        busy[scope, default: 0]
    }

    /// Isolated to this actor, so it cannot begin before `enqueue` suspends inside `withTaskCancellationHandler`,
    /// whose handler runs at once for a caller cancelled before then and cancels this task: the check below sees
    /// every cancellation that lands before the operation starts.
    private func start<T: Sendable>(
        after previous: Task<Void, Never>?, _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        await previous?.value
        try Task.checkCancellation()
        return try await operation()
    }

    private func finished(_ scope: Scope) {
        busy[scope, default: 1] -= 1
        if busy[scope] == 0 {
            busy.removeValue(forKey: scope)
            tails.removeValue(forKey: scope)
        }
    }
}
