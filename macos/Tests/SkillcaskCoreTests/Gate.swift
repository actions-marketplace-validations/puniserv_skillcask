/// A one-shot gate, as the UI tests' `Gate`: `wait()` suspends until `open()`; `arrived()` returns once someone
/// waits. Orders concurrent work without sleeps.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []
    private var arrivals = 0

    func wait() async {
        arrivals += 1
        for watcher in watchers {
            watcher.resume()
        }
        watchers.removeAll()
        if isOpen {
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Suspends until a caller is blocked in `wait()`.
    func arrived() async {
        if arrivals > 0 {
            return
        }
        await withCheckedContinuation { watchers.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}
