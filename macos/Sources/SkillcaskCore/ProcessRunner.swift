import Foundation
import os

/// Spawns the CLI. Both pipes are drained concurrently (a full pipe would block the child) through
/// `readabilityHandler`, the exit comes through `terminationHandler`, and a cancelled caller terminates the child
/// with SIGTERM, then SIGKILL after a grace period. Nothing here blocks a thread of the cooperative pool: the pool
/// is one thread per core and stops dead once that many are blocked, and `Process.waitUntilExit()` on top of that
/// can miss its wake-up when the child exits around the call and then never returns. One `Process` per call; the
/// actor only owns the table of running children.
public actor ProcessRunner: CLIClient {
    public struct Limits: Hashable, Sendable {
        /// Bytes of stdout kept; a document larger than this is a bug upstream, not something to render.
        public var stdoutBytes: Int = 8 << 20
        public var stderrBytes: Int = 1 << 20
        /// Time between SIGTERM and SIGKILL.
        public var grace: Duration = .seconds(5)

        public init() {}
    }

    public let executable: URL
    /// Read at every spawn, so a Settings change reaches the next run.
    public let source: EnvironmentSource
    public let limits: Limits
    private var running: [UUID: Process] = [:]

    /// The policy the next child gets.
    public nonisolated var policy: EnvironmentPolicy {
        source.policy
    }

    public init(executable: URL, policy: EnvironmentPolicy = .default, limits: Limits = Limits()) {
        self.init(executable: executable, source: EnvironmentSource(policy), limits: limits)
    }

    /// A runner over a shared, live policy (the app's: `AppStore.environment`).
    public init(executable: URL, source: EnvironmentSource, limits: Limits = Limits()) {
        self.executable = executable
        self.source = source
        self.limits = limits
    }

    public func run(
        _ invocation: Invocation, onLine: @escaping @Sendable (OutputLine) -> Void
    ) async throws(CLIError) -> RunResult {
        let id = UUID()
        let start = ContinuousClock.now
        let process = Process()
        process.executableURL = executable
        process.arguments = invocation.argv
        process.currentDirectoryURL = invocation.scope.root
        let policy = source.policy
        process.environment = policy.environment()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let stdin: Pipe?
        switch invocation.stdin {
        case .null:
            stdin = nil
            process.standardInput = FileHandle.nullDevice
        case .text:
            stdin = Pipe()
            process.standardInput = stdin
        }
        // Installed before `run()`: Foundation calls it exactly once, on a queue of its own, however early the
        // child exits. Only this handler ends the stream; nothing else looks at `isRunning` to decide the exit.
        let (exited, exit) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in exit.finish() }
        do {
            try process.run()
        } catch {
            throw .launchFailed(error.localizedDescription)
        }
        running[id] = process
        defer { running.removeValue(forKey: id) }
        if case .text(let text) = invocation.stdin, let stdin {
            try? stdin.fileHandleForWriting.write(contentsOf: Data(text.utf8))
            try? stdin.fileHandleForWriting.close()
        }

        let limits = limits
        let pump = Task.detached {
            async let out = Self.drain(stdout.fileHandleForReading, limit: limits.stdoutBytes) { onLine(.stdout($0)) }
            async let err = Self.drain(stderr.fileHandleForReading, limit: limits.stderrBytes) { onLine(.stderr($0)) }
            let collected = (await out, await err)
            for await _ in exited {}
            return collected
        }
        let (out, err) = await withTaskCancellationHandler {
            await pump.value
        } onCancel: {
            Task { await self.terminate(id) }
        }
        let status: ExitStatus =
            process.terminationReason == .uncaughtSignal
            ? .signaled(process.terminationStatus) : .exited(process.terminationStatus)
        if Task.isCancelled {
            throw .cancelled
        }
        if out.truncated {
            throw .outputTooLarge(limit: limits.stdoutBytes)
        }
        var result = RunResult(
            invocation: invocation, status: status, stdout: out.data, stderr: String(decoding: err.data, as: UTF8.self),
            duration: ContinuousClock.now - start)
        result.environmentOverrides = policy.appliedOverrideNames
        return result
    }

    /// SIGTERM, then SIGKILL after the grace period if the child is still there. Safe mid-mutation: the CLI writes
    /// atomically and the next run cleans its leftovers.
    public func terminate(_ id: UUID) async {
        guard let process = running[id], process.isRunning else { return }
        process.terminate()
        try? await Task.sleep(for: limits.grace)
        if process.isRunning {
            // `terminate()` reaches the child's subtasks too; so must the kill, or a helper keeps the pipes open.
            if killpg(process.processIdentifier, SIGKILL) != 0 {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    public var runningCount: Int {
        running.count
    }

    private struct Drained: Sendable {
        var data = Data()
        var truncated = false
    }

    /// What one pipe has produced so far. Mutated only from the handle's handler, which Foundation serializes; the
    /// lock is what lets the handler capture it.
    private struct Draining: Sendable {
        var drained = Drained()
        var pending = Data()
        var total = 0

        /// Keeps up to `limit` bytes and returns the lines `chunk` completed.
        mutating func append(_ chunk: Data, limit: Int) -> [String] {
            total += chunk.count
            if drained.data.count < limit {
                drained.data.append(chunk.prefix(limit - drained.data.count))
            }
            drained.truncated = total > limit
            pending.append(chunk)
            var lines: [String] = []
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...newline)
            }
            return lines
        }

        /// The result, and the unterminated last line if there is one.
        mutating func finish() -> (Drained, String?) {
            (drained, pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self))
        }
    }

    /// Reads to EOF through `readabilityHandler`, which Foundation calls as data arrives, one call at a time per
    /// handle, so lines reach `onLine` in order and no thread waits on the pipe. EOF is an empty `availableData`;
    /// the handler then unhooks itself, which is also what guarantees a single resume.
    private nonisolated static func drain(
        _ handle: FileHandle, limit: Int, onLine: @escaping @Sendable (String) -> Void
    ) async -> Drained {
        let state = OSAllocatedUnfairLock(initialState: Draining())
        return await withCheckedContinuation { continuation in
            handle.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard chunk.isEmpty else {
                    for line in state.withLock({ $0.append(chunk, limit: limit) }) {
                        onLine(line)
                    }
                    return
                }
                handle.readabilityHandler = nil
                let (drained, tail) = state.withLock { $0.finish() }
                if let tail {
                    onLine(tail)
                }
                continuation.resume(returning: drained)
            }
        }
    }
}
