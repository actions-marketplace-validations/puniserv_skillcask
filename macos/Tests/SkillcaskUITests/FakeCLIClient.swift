import Foundation
import SkillcaskCore

/// A one-shot gate: `wait()` suspends until `open()`; `arrived()` returns once someone waits. Makes "a slow answer
/// still in flight" deterministic without sleeps (swift-testing-practices, "Store tests with a CLIClient fake").
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

/// Scripted answers per scope and command, consumed in order; records every invocation. An unscripted call fails
/// with a readable `CLIError` naming the key, so a store that runs an unexpected command fails instead of hanging.
actor FakeCLIClient: CLIClient {
    struct Key: Hashable {
        let scope: Scope
        let command: Invocation.Command
    }

    /// One scripted answer: stdout, exit code and the lines streamed before it, or an error.
    enum Answer {
        case result(stdout: String, exit: Int32, lines: [OutputLine])
        case error(CLIError)
    }

    private var answers: [Key: [(answer: Answer, gate: Gate?)]] = [:]
    private(set) var invocations: [Invocation] = []

    /// The commands run so far, in order.
    var commands: [Invocation.Command] {
        invocations.map(\.command)
    }

    /// Queues `answer` for `command` in `scope`; with `gate`, that one answer is held until the gate opens.
    func script(_ command: Invocation.Command, in scope: Scope, _ answer: Answer, gate: Gate? = nil) {
        answers[Key(scope: scope, command: command), default: []].append((answer, gate))
    }

    /// A document answer: `json` on stdout with `exit`.
    func json(_ command: Invocation.Command, in scope: Scope, _ json: String, exit: Int32 = 0, gate: Gate? = nil) {
        script(command, in: scope, .result(stdout: json, exit: exit, lines: []), gate: gate)
    }

    /// A mutation answer: nothing on stdout, `lines` streamed, `exit`.
    func lines(_ command: Invocation.Command, in scope: Scope, _ lines: [String], exit: Int32 = 0, gate: Gate? = nil) {
        script(command, in: scope, .result(stdout: "", exit: exit, lines: lines.map(OutputLine.stdout)), gate: gate)
    }

    func run(
        _ invocation: Invocation, onLine: @escaping @Sendable (OutputLine) -> Void
    ) async throws(CLIError) -> RunResult {
        invocations.append(invocation)
        let key = Key(scope: invocation.scope, command: invocation.command)
        guard let next = answers[key]?.first else {
            throw .failed(code: .other(99), message: "unscripted: \(invocation.displayCommand)", hint: nil, stderr: "")
        }
        answers[key]?.removeFirst()
        if let gate = next.gate {
            await gate.wait()
        }
        if Task.isCancelled {
            throw .cancelled
        }
        switch next.answer {
        case .error(let error):
            throw error
        case .result(let stdout, let exit, let lines):
            for line in lines {
                onLine(line)
            }
            return RunResult(invocation: invocation, status: .exited(exit), stdout: Data(stdout.utf8), stderr: "")
        }
    }
}
