import Foundation

/// The live client's two guards, around any `CLIClient` (the app wraps `ProcessRunner` in it):
///
/// - A project scope whose folder has no skills.toml runs nothing but what `Invocation.needsManifest` allows: the
///   CLI would walk up to the nearest parent with a skills.toml (`src/project.rs` `find_root`) and act on that
///   project instead. The refusal is the error the CLI gives where no project exists at all (`src/manifest.rs`
///   `Manifest::load`: `skills.toml not found`, hint `run skillcask init`), so the app shows its Set Up block.
///   Checked at every spawn, so a folder whose skills.toml went away since the sidebar's check is refused too.
/// - A read-only command (`Invocation.isReadOnly`) that has not answered within its limit is cancelled (the runner
///   terminates the child) and fails with `CLIError.timedOut`. Two limits: `readTimeout` (2 min) for the
///   reads that stay on disk (`status`, `audit`, `doctor`, `info <skill>`, `projects`, `config`) and for
///   `self-check` (one small file, D35), and
///   `networkReadTimeout` (15 min) for the ones that talk to registries (`Invocation.needsNetwork`: `outdated`
///   queries every registry, `diff` and `diff --to` download the archives they compare, `info <package>` downloads
///   the dist, `search` asks every source). Those can legitimately take minutes on a slow link or a large
///   package, so 2 minutes would fail real work; 15 minutes still ends a run that hangs (a stalled TLS read, a
///   git server that never answers), which nothing else would, since the user cannot cancel a read. Mutations
///   have no timeout: the user cancels them.
public struct GuardedClient: CLIClient {
    /// How long a read that stays on disk may take.
    public static let readTimeout: Duration = .seconds(120)
    /// How long a read that talks to registries may take (`Invocation.needsNetwork`).
    public static let networkReadTimeout: Duration = .seconds(15 * 60)

    public let base: any CLIClient
    public let readTimeout: Duration
    public let networkReadTimeout: Duration
    private let manifestExists: @Sendable (URL) -> Bool

    /// - Parameter manifestExists: Whether `root/skills.toml` exists; the live check reads the disk.
    public init(
        _ base: any CLIClient, readTimeout: Duration = GuardedClient.readTimeout,
        networkReadTimeout: Duration = GuardedClient.networkReadTimeout,
        manifestExists: @escaping @Sendable (URL) -> Bool = GuardedClient.manifestOnDisk
    ) {
        self.base = base
        self.readTimeout = readTimeout
        self.networkReadTimeout = networkReadTimeout
        self.manifestExists = manifestExists
    }

    /// The limit `invocation` runs under; nil for a mutation (no limit).
    public func limit(for invocation: Invocation) -> Duration? {
        guard invocation.isReadOnly else { return nil }
        // `self-check` makes one request for one small file: D35 gives it the 2 minutes of a read on disk.
        if invocation.command == .selfCheck {
            return readTimeout
        }
        return invocation.needsNetwork ? networkReadTimeout : readTimeout
    }

    /// `root/skills.toml` is a file.
    public static let manifestOnDisk: @Sendable (URL) -> Bool = { root in
        var isDirectory: ObjCBool = false
        let path = root.appending(path: "skills.toml").path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    /// What the guard answers for a project folder without skills.toml: the CLI's own words.
    public static let notSetUp = CLIError.failed(
        code: .problem, message: "skills.toml not found", hint: "run skillcask init", stderr: "")

    public func run(
        _ invocation: Invocation, onLine: @escaping @Sendable (OutputLine) -> Void
    ) async throws(CLIError) -> RunResult {
        if invocation.needsManifest, !manifestExists(invocation.scope.root) {
            throw Self.notSetUp
        }
        guard let limit = limit(for: invocation) else {
            return try await base.run(invocation, onLine: onLine)
        }
        let base = base
        let outcome = await withTaskGroup(of: Result<RunResult, CLIError>?.self) { group in
            group.addTask {
                do throws(CLIError) {
                    return .success(try await base.run(invocation, onLine: onLine))
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                // A cancelled sleep is the run answering first (or the caller cancelling): no verdict of its own.
                guard (try? await Task.sleep(for: limit)) != nil else { return nil }
                return .failure(.timedOut(after: limit))
            }
            // The first verdict wins; cancelling the other stops the timer, or the child through the runner.
            while let next = await group.next() {
                if let next {
                    group.cancelAll()
                    return next
                }
            }
            return .failure(.cancelled)
        }
        return try outcome.get()
    }
}
