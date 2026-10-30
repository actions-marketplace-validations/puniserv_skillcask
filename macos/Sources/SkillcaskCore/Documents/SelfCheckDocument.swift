/// `self-check --json` (D51): the running CLI's version, the latest the tap's cask names (`null` when the cask held
/// no version the CLI could read) and whether that is newer by SemVer precedence. Keys as D32 adds them; unknown
/// ones are ignored.
public struct SelfCheckDocument: Decodable, Hashable, Sendable {
    public let version: String
    public let latest: String?
    public let newer: Bool

    public init(version: String, latest: String?, newer: Bool) {
        self.version = version
        self.latest = latest
        self.newer = newer
    }

    /// `latest` read again strictly (`Version.init?(strict:)`): nil when it is null or anything but a plain
    /// version, so nothing else from the response reaches a URL or the screen.
    public var latestVersion: Version? {
        latest.flatMap(Version.init(strict:))
    }
}

/// What `CLIClient.selfCheck` learnt: the document, or that this CLI predates `self-check` (a path the user set in
/// Settings, older than the app); the bundled CLI always has it.
public enum SelfCheckOutcome: Hashable, Sendable {
    case checked(SelfCheckDocument)
    case unsupported
}

extension CLIClient {
    /// Runs `self-check --json` outside any project (the CLI needs none). Exit 3 and every other failure throw as
    /// usual (`CLIError.failed` keeps the CLI's `error:` and `hint:` lines); under `GuardedClient` a run longer than
    /// 2 minutes throws `.timedOut`. A CLI that does not know the command answers `.unsupported`, whatever its
    /// version says: development builds carry the last release's number.
    public func selfCheck(capabilities: Capabilities) async throws(CLIError) -> SelfCheckOutcome {
        let result = try await run(Invocation(.selfCheck, in: .personal, capabilities: capabilities))
        if let failure = result.failure(), Self.isUnknownSelfCheck(failure) {
            return .unsupported
        }
        return .checked(try result.document(SelfCheckDocument.self))
    }

    /// An older CLI's refusal of the word `self-check`: `unknown command "self-check" (no skillcask-self-check on
    /// PATH)` with exit 1 (`src/main.rs` `plugin`, every release since 0.9.0), or clap's `unrecognized subcommand
    /// 'self-check'` should a release parse it as a usage error (exit 1 here, 2 in clap's default).
    static func isUnknownSelfCheck(_ error: CLIError) -> Bool {
        guard case .failed(let code, let message, _, _) = error, code == .problem || code == .signIn else {
            return false
        }
        return message.hasPrefix(#"unknown command "self-check""#)
            || message.hasPrefix("unrecognized subcommand 'self-check'")
    }
}
