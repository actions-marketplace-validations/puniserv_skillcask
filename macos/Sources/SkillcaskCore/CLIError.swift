import Foundation

/// Everything that can go wrong between the app and the `skillcask` binary. The UI maps each case to copy; nothing
/// here is user-facing text.
public enum CLIError: Error, Hashable, Sendable {
    /// No executable `skillcask` at the configured path or on the search path.
    case binaryMissing(searched: [String])
    /// The configured path is the running Skillcask app itself (`Locator.isSelf`), never probed: running it would
    /// start another app.
    case binaryIsApp(path: String)
    /// The binary answered `--version` with something that is not a skillcask version line.
    case unreadableVersion(output: String)
    case tooOld(found: Version, needs: Version)
    /// The request needs a `Capabilities.Feature` this CLI does not have.
    case unsupported(feature: String)
    /// The command could not be built: an empty package list, a search to remember without a choice, …
    case invalidInvocation(String)
    /// `Process.run()` threw: the file is not executable, the working directory is gone, …
    case launchFailed(String)
    /// The CLI exited non-zero without printing a document; `message` and `hint` come from stderr.
    case failed(code: ExitCode, message: String, hint: String?, stderr: String)
    /// The task was cancelled and the child terminated on our request.
    case cancelled
    /// The child died from a signal we did not send.
    case killed(signal: Int32)
    /// Exit 0 but nothing on stdout where a `--json` document was expected.
    case noDocument
    /// stdout was not the expected document; `raw` is kept for the Details disclosure, never parsed again.
    case decode(String, raw: Data)
    case outputTooLarge(limit: Int)
    /// A read-only command did not answer within `after` (`GuardedClient.readTimeout`); the app stopped it.
    case timedOut(after: Duration)
}
