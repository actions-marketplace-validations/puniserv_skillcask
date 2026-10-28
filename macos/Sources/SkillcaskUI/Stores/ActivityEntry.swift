import Foundation
import SkillcaskCore
import SkillcaskDomain

extension ActionRunner {
    /// Where a store that runs reads hands their Activity rows (`ActionRunner.record(_:)`); nil records nothing.
    public typealias ActivitySink = @MainActor (ActivityEntry) -> Void

    /// What one read-only command left for its Activity row: its command line, how it exited, its stderr and the
    /// environment names it got. Collected by the store that ran the read (`ScopeStore`, `ReviewStore`).
    public struct ReadTrace: Hashable, Sendable {
        public var command: String
        public var status: ExitStatus?
        public var stderr = ""
        public var environmentOverrides: [String] = []

        public init(command: String, status: ExitStatus? = nil) {
            self.command = command
            self.status = status
        }
    }

    /// One finished run of this session (S15), newest first in `ActionRunner.activity`: window runs, sheet runs,
    /// each item of a batch, and the reads the user started (opening a scope, ⌘R, Check for updates, the Review
    /// Update sheet's `diff`; `ScopeStore` and `ReviewStore` say which). Bounded so a long session stays small: the
    /// newest `limit` runs, each keeping the last `transcriptLimit` lines of at most `lineLimit` characters and
    /// `characterLimit` characters in all (`omittedLines` counts what was dropped). Nothing secret is kept: the
    /// command is `Invocation.displayCommand` (stdin never appears in it), the environment by name only.
    public struct ActivityEntry: Identifiable, Hashable, Sendable {
        /// Runs kept per session.
        public static let limit = 100
        /// Transcript lines kept per run: the last ones, where a failure says why.
        public static let transcriptLimit = 1_000
        /// Characters kept per transcript line; a longer line ends in `…`.
        public static let lineLimit = 2_000
        /// Characters kept per run, all lines together: the newest lines that fit.
        public static let characterLimit = 200_000

        /// How a run ended, which the drawer says in one word (`ActivityCopy.word(for:)`).
        public enum Ending: Hashable, Sendable {
            /// Exit 0.
            case ok
            /// A non-zero exit with its document (`doctor` exits 1 with problems): the run answered.
            case findings
            /// A non-zero exit without a document.
            case failed(ExitCode)
            /// Exit 1 because the project's policy refused the source (AddSkill-States, drawn amber).
            case refused
            /// Cancel terminated the child.
            case cancelled
            /// The child died from a signal the app did not send.
            case killed
            /// A read-only command passed `GuardedClient.readTimeout` and the app stopped it.
            case timedOut
            /// The output was missing, not the expected document, or too large.
            case unreadable
            /// The command never ran: it could not be built, or the binary could not be launched.
            case notRun
        }

        public let id: UUID
        /// The run's progressive title as the list header or sheet showed it (`Syncing with skills.lock…`).
        public let title: String
        /// What the run did, in plain words: the toast's text on success (`Checked api`), the failure's title
        /// otherwise (`Couldn’t sync sql-review.`); empty when the caller words none (a batch item).
        public let headline: String
        /// `skillcask install`, or `ActionCopy.unbuilt` when the command could not be built; a read of several
        /// commands (the offline trio) has one command line each, separated by newlines.
        public let command: String
        public let scope: Scope
        public let startedAt: Date
        public let duration: Duration
        /// How the child ended; nil when it never ran (the command could not be built or launched).
        public let status: ExitStatus?
        public let error: CLIError?
        /// The last `transcriptLimit` lines the child printed, each clipped to `lineLimit`.
        public let transcript: [OutputLine]
        /// Lines dropped from the front of the transcript.
        public let omittedLines: Int
        /// The command changes the scope (it went through `MutationQueue`), so it may have written skills.lock.
        public let isMutation: Bool
        /// The command prints a document (`--json`): a non-zero exit with one is `.findings`, not a failure.
        public let expectsDocument: Bool
        /// The Settings environment names the child got (`RunResult.environmentOverrides`); never their values.
        public let environmentOverrides: [String]

        public init(
            id: UUID = UUID(), title: String, headline: String, command: String, scope: Scope, startedAt: Date,
            duration: Duration, status: ExitStatus?, error: CLIError?, transcript: [OutputLine], omittedLines: Int = 0,
            isMutation: Bool, expectsDocument: Bool, environmentOverrides: [String] = []
        ) {
            self.id = id
            self.title = title
            self.headline = headline
            self.command = command
            self.scope = scope
            self.startedAt = startedAt
            self.duration = duration
            self.status = status
            self.error = error
            let kept = Self.bounded(transcript)
            self.transcript = kept
            self.omittedLines = omittedLines + transcript.count - kept.count
            self.isMutation = isMutation
            self.expectsDocument = expectsDocument
            self.environmentOverrides = environmentOverrides
        }

        /// The ending the drawer's word and colour come from.
        public var ending: Ending {
            guard let error else {
                if let status, !status.isSuccess, expectsDocument { return .findings }
                return .ok
            }
            switch error {
            case .failed(let code, _, _, _):
                // The banner's own test for a policy refusal: the one `.problem` it draws amber.
                return code == .problem && ErrorCopy.message(for: error).severity == .warning ? .refused : .failed(code)
            case .cancelled:
                return .cancelled
            case .killed:
                return .killed
            case .timedOut:
                return .timedOut
            case .noDocument, .decode, .outputTooLarge:
                return .unreadable
            case .binaryMissing, .binaryIsApp, .unreadableVersion, .tooOld, .unsupported, .invalidInvocation,
                .launchFailed:
                return .notRun
            }
        }

        /// Whether the run may have rewritten skills.lock: a mutation that ended at exit 0.
        public var mayHaveWrittenLock: Bool {
            isMutation && ending == .ok
        }

        /// The scope's skills.lock, which the CLI keeps beside `manifest` (`AppStore.manifest(of:)`).
        public func lockFile(beside manifest: URL) -> URL {
            manifest.deletingLastPathComponent().appending(path: "skills.lock")
        }

        /// The row of a read the user started: `headline` on success, `failure` otherwise; `status` (the failing
        /// command's exit), else the first trace's, is the row's; every trace's stderr is the transcript.
        public static func read(
            headline: String, failure: String, scope: Scope, startedAt: Date, traces: [ReadTrace], error: CLIError?,
            expectsDocument: Bool = true, status: ExitStatus? = nil, now: Date = Date()
        ) -> ActivityEntry {
            var names: [String] = []
            for name in traces.flatMap(\.environmentOverrides) where !names.contains(name) {
                names.append(name)
            }
            let transcript = traces.flatMap { trace in
                trace.stderr.split(whereSeparator: \.isNewline).map { OutputLine.stderr(String($0)) }
            }
            return ActivityEntry(
                title: headline, headline: error == nil ? headline : failure,
                command: traces.map(\.command).joined(separator: "\n"), scope: scope, startedAt: startedAt,
                duration: .seconds(max(0, now.timeIntervalSince(startedAt))), status: status ?? traces.first?.status,
                error: error, transcript: transcript, isMutation: false, expectsDocument: expectsDocument,
                environmentOverrides: names)
        }

        /// The newest lines within `transcriptLimit` and `characterLimit`, each clipped to `lineLimit`.
        private static func bounded(_ transcript: [OutputLine]) -> [OutputLine] {
            var kept: [OutputLine] = []
            var characters = 0
            for line in transcript.suffix(transcriptLimit).reversed() {
                let clipped = clipped(line)
                characters += clipped.text.count
                if characters > characterLimit { break }
                kept.append(clipped)
            }
            return kept.reversed()
        }

        private static func clipped(_ line: OutputLine) -> OutputLine {
            guard line.text.count > lineLimit else { return line }
            let text = String(line.text.prefix(lineLimit)) + "…"
            switch line {
            case .stdout: return .stdout(text)
            case .stderr: return .stderr(text)
            }
        }
    }
}
