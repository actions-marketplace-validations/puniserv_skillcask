import Foundation
import Testing
import os

@testable import SkillcaskCore

/// Ordered with `Gate`s, never with sleeps or wall-clock bounds: a slow machine changes no outcome.
@Suite struct MutationQueueTests {
    let a = Scope.project(URL(fileURLWithPath: "/tmp/a"))
    let b = Scope.project(URL(fileURLWithPath: "/tmp/b"))

    @Test(.timeLimit(.minutes(1))) func sameScopeRunsInOrder() async throws {
        let queue = MutationQueue()
        let order = OSAllocatedUnfairLock(initialState: [String]())
        let gate = Gate()
        let first = Task {
            try await queue.enqueue(in: a) {
                order.withLock { $0.append("first start") }
                await gate.wait()
                order.withLock { $0.append("first end") }
            }
        }
        await gate.arrived()
        let second = Task { try await queue.enqueue(in: a) { order.withLock { $0.append("second") } } }
        // `second` has queued behind `first` (two pending) and has not run while `first` holds the scope.
        while await queue.pending(in: a) < 2 {
            await Task.yield()
        }
        #expect(order.withLock { $0 } == ["first start"])
        await gate.open()
        try await first.value
        try await second.value
        #expect(order.withLock { $0 } == ["first start", "first end", "second"])
        #expect(await !queue.isBusy(a))
    }

    /// Both operations are inside their run at once: each waits on its own gate, and both arrive before either
    /// opens. Serialising the scopes would leave `b` waiting behind `a` and the test at its time limit.
    @Test(.timeLimit(.minutes(1))) func differentScopesOverlap() async throws {
        let queue = MutationQueue()
        let inA = Gate()
        let inB = Gate()
        let one = Task { try await queue.enqueue(in: a) { await inA.wait() } }
        let two = Task { try await queue.enqueue(in: b) { await inB.wait() } }
        await inA.arrived()
        await inB.arrived()
        #expect(await queue.isBusy(a))
        #expect(await queue.isBusy(b))
        await inA.open()
        await inB.open()
        try await one.value
        try await two.value
    }

    @Test(.timeLimit(.minutes(1))) func cancellingAWaitingMutationLeavesTheOthersAlone() async throws {
        let queue = MutationQueue()
        let ran = OSAllocatedUnfairLock(initialState: [String]())
        let gate = Gate()
        let first = Task {
            try await queue.enqueue(in: a) {
                await gate.wait()
                ran.withLock { $0.append("first") }
            }
        }
        await gate.arrived()
        let second = Task { try await queue.enqueue(in: a) { ran.withLock { $0.append("second") } } }
        let third = Task { try await queue.enqueue(in: a) { ran.withLock { $0.append("third") } } }
        // `first` holds the scope until the gate opens, so `second` is cancelled while it waits (or before it
        // queued: either way it must never run).
        second.cancel()
        await gate.open()
        await #expect(throws: CancellationError.self) { try await second.value }
        try await first.value
        try await third.value
        #expect(ran.withLock { $0 } == ["first", "third"])
    }

    @Test func resultAndErrorPassThrough() async throws {
        let queue = MutationQueue()
        #expect(try await queue.enqueue(in: a) { 42 } == 42)
        await #expect(throws: CLIError.noDocument) { try await queue.enqueue(in: a) { throw CLIError.noDocument } }
        #expect(await !queue.isBusy(a))
    }
}
