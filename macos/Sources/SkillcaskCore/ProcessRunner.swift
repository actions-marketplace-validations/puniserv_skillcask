import Foundation

/// Spawns the CLI. Both pipes are drained concurrently (a full pipe would block the child), the exit is awaited in
/// the same detached task after the pipes close, and a cancelled caller terminates the child with SIGTERM, then
/// SIGKILL after a grace period. One `Process` per call; the actor only owns the table of running children.
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
    public let policy: EnvironmentPolicy
    public let limits: Limits
    private var running: [UUID: Process] = [:]

    public init(executable: URL, policy: EnvironmentPolicy = .default, limits: Limits = Limits()) {
        self.executable = executable
        self.policy = policy
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
            process.waitUntilExit()
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
        return RunResult(
            invocation: invocation, status: status, stdout: out.data, stderr: String(decoding: err.data, as: UTF8.self),
            duration: ContinuousClock.now - start)
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

    /// Reads to EOF on a thread of its own (the file handle API blocks); lines go to `onLine` as they complete.
    private nonisolated static func drain(
        _ handle: FileHandle, limit: Int, onLine: @escaping @Sendable (String) -> Void
    ) async -> Drained {
        await Task.detached {
            var drained = Drained()
            var pending = Data()
            var total = 0
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    break
                }
                total += chunk.count
                if drained.data.count < limit {
                    drained.data.append(chunk.prefix(limit - drained.data.count))
                }
                drained.truncated = total > limit
                pending.append(chunk)
                while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    onLine(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
                    pending.removeSubrange(pending.startIndex...newline)
                }
            }
            if !pending.isEmpty {
                onLine(String(decoding: pending, as: UTF8.self))
            }
            return drained
        }
        .value
    }
}
