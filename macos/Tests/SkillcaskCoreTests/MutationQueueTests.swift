import Foundation
import Testing
import os

@testable import SkillcaskCore

@Suite struct MutationQueueTests {
    let a = Scope.project(URL(fileURLWithPath: "/tmp/a"))
    let b = Scope.project(URL(fileURLWithPath: "/tmp/b"))

    @Test(.timeLimit(.minutes(1))) func sameScopeRunsInOrder() async throws {
        let queue = MutationQueue()
        let order = OSAllocatedUnfairLock(initialState: [String]())
        async let first: Void = queue.enqueue(in: a) {
            order.withLock { $0.append("first start") }
            try await Task.sleep(for: .milliseconds(200))
            order.withLock { $0.append("first end") }
        }
        try await Task.sleep(for: .milliseconds(20))
        async let second: Void = queue.enqueue(in: a) {
            order.withLock { $0.append("second") }
        }
        #expect(await queue.isBusy(a))
        _ = try await (first, second)
        #expect(order.withLock { $0 } == ["first start", "first end", "second"])
        #expect(await !queue.isBusy(a))
    }

    @Test(.timeLimit(.minutes(1))) func differentScopesOverlap() async throws {
        let queue = MutationQueue()
        let clock = ContinuousClock()
        let start = clock.now
        async let one: Void = queue.enqueue(in: a) { try await Task.sleep(for: .milliseconds(300)) }
        async let two: Void = queue.enqueue(in: b) { try await Task.sleep(for: .milliseconds(300)) }
        _ = try await (one, two)
        #expect(clock.now - start < .milliseconds(550))
    }

    @Test(.timeLimit(.minutes(1))) func cancellingAWaitingMutationLeavesTheOthersAlone() async throws {
        let queue = MutationQueue()
        let ran = OSAllocatedUnfairLock(initialState: [String]())
        let first = Task {
            try await queue.enqueue(in: a) {
                try await Task.sleep(for: .milliseconds(200))
                ran.withLock { $0.append("first") }
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        let second = Task { try await queue.enqueue(in: a) { ran.withLock { $0.append("second") } } }
        let third = Task { try await queue.enqueue(in: a) { ran.withLock { $0.append("third") } } }
        try await Task.sleep(for: .milliseconds(20))
        second.cancel()
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
