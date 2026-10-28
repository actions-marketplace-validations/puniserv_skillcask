/// The seam between the app and the CLI. `ProcessRunner` is the only production implementation; tests use a fake
/// that returns scripted results and records invocations.
public protocol CLIClient: Sendable {
    /// Runs to completion. Cancelling the calling task terminates the child and throws `CLIError.cancelled`.
    func run(_ invocation: Invocation) async throws(CLIError) -> RunResult

    /// Like `run`, with every line handed to `onLine` as it arrives, for the live log of a long mutation.
    func run(
        _ invocation: Invocation, onLine: @escaping @Sendable (OutputLine) -> Void
    ) async throws(CLIError) -> RunResult
}

extension CLIClient {
    public func run(_ invocation: Invocation) async throws(CLIError) -> RunResult {
        try await run(invocation) { _ in }
    }

    /// Decoded in one step: the document, or the error the missing document stands for.
    public func document<T: Decodable & Sendable>(
        _ type: T.Type, for invocation: Invocation
    ) async throws(CLIError) -> T {
        try await run(invocation).document(type)
    }

    /// `--version` through the gate: the parsed `Capabilities`, or why the binary cannot be used.
    public func capabilities(via invocation: Invocation) async throws(CLIError) -> Capabilities {
        let result = try await run(invocation)
        let output = result.stdoutText
        guard let version = Version(cliOutput: output) else {
            throw .unreadableVersion(output: output.isEmpty ? result.stderr : output)
        }
        let capabilities = Capabilities(version: version)
        if capabilities.isTooOld {
            throw .tooOld(found: version, needs: Capabilities.minimum)
        }
        return capabilities
    }
}
