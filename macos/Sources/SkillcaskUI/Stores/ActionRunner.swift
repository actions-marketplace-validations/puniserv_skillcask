import Foundation
import Observation
import SkillcaskCore
import SkillcaskDomain

/// Runs the commands that change or check a scope (ADR §3): mutations through `MutationQueue` so one runs at a
/// time per scope, `doctor` without `--fix` directly. While a command runs, `current` carries its live transcript
/// and a cancel; when it ends, an `ActivityEntry` is appended (S15), `outcome` becomes the toast or the failure
/// banner (S11), and the scope's store runs its targeted refresh.
///
/// Wired here: `sync` (`install`), `check` (`doctor`), `repair` (`doctor --fix`), `restoreFromLock`
/// (`install --frozen`). Add, update, remove and adopt arrive with their sheets (P3-5, P3-6, P3-8): they will call
/// `run(_:title:in:)` with their `Invocation.Command` and the same bookkeeping applies.
@MainActor @Observable public final class ActionRunner {
    /// A command in flight: what the list header and the Activity drawer show.
    public struct RunningAction: Identifiable {
        public let id: UUID
        /// "Syncing…", from `ActionCopy`.
        public let title: String
        public let scope: Scope
        /// `skillcask install`, for the Activity drawer.
        public let command: String
        public let startedAt: Date
        public fileprivate(set) var lines: [OutputLine] = []
        fileprivate let task: Task<Void, Never>?

        /// Terminates the child (SIGTERM, then SIGKILL after the grace period); the outcome reads `Cancelled.`
        public func cancel() {
            task?.cancel()
        }
    }

    /// One finished run of this session, newest first in `activity`.
    public struct ActivityEntry: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let title: String
        public let command: String
        public let startedAt: Date
        public let duration: Duration
        /// How the child ended; nil when it never ran (the command could not be built or launched).
        public let status: ExitStatus?
        public let error: CLIError?
        public let transcript: [OutputLine]
    }

    /// What the window shows when a run ends: the toast at the bottom of the list column, or the banner at its top.
    public enum Outcome: Identifiable, Hashable, Sendable {
        case toast(ToastMessage)
        case banner(UserMessage, id: UUID)

        public var id: UUID {
            switch self {
            case .toast(let message): message.id
            case .banner(_, let id): id
            }
        }
    }

    private let queue: MutationQueue

    // MARK: - State

    public private(set) var current: RunningAction?
    public private(set) var activity: [ActivityEntry] = []
    /// The toast or banner of the last finished run; the window clears it when dismissed or timed out.
    public var outcome: Outcome?

    /// The last run that ended in a failure banner, so Retry can run it again (never automatically).
    private struct FailedRun {
        let command: Invocation.Command
        let title: String
        let outcome: @Sendable (String) -> String
        weak var store: ScopeStore?
        /// Set when the run ended in an integrity failure: `retry()` refuses it.
        var isIntegrity = false
    }

    @ObservationIgnored private var failedRun: FailedRun?

    public init(queue: MutationQueue) {
        self.queue = queue
    }

    /// The success toast of `outcome`, bindable for `View.toast`: setting nil clears a showing toast only.
    public var toast: ToastMessage? {
        get {
            if case .toast(let message) = outcome { message } else { nil }
        }
        set {
            if let newValue {
                outcome = .toast(newValue)
            } else if case .toast = outcome {
                outcome = nil
            }
        }
    }

    /// The failure banner of `outcome`, if that is what the last run left.
    public var banner: UserMessage? {
        if case .banner(let message, _) = outcome { message } else { nil }
    }

    /// Dismisses the banner; an integrity failure stays until this is called (Running board).
    public func dismissBanner() {
        if case .banner = outcome {
            outcome = nil
        }
    }

    /// Re-runs the last action that failed (same command, title and outcome, in the same scope) and clears its
    /// banner. Only the user's Retry calls it: nothing is retried automatically, and the banner offers Retry for
    /// network failures alone (`FailureBanner.showsRetry`). An integrity failure is refused, not even from a stray
    /// call: its run is kept but marked, and `retry()` returns nil for it. Also nil when no run has failed since
    /// the last success, when the scope's store is gone, or while another run is in flight. Returns the new run's
    /// task.
    @discardableResult public func retry() -> Task<Void, Never>? {
        guard let failedRun, !failedRun.isIntegrity, let store = failedRun.store, current == nil else { return nil }
        outcome = nil
        return Task { await run(failedRun.command, title: failedRun.title, outcome: failedRun.outcome, in: store) }
    }

    /// Previews: shows `title` as a run in flight in `scope`, with no child process behind it.
    func preloadRunning(title: String, in scope: Scope) {
        current = RunningAction(
            id: UUID(), title: title, scope: scope, command: "", startedAt: Date(), task: nil)
    }

    // MARK: - Derived

    /// One run at a time in the whole app (`run` refuses a second while `current` is set), so every scope's
    /// toolbar and Overview actions are disabled while any run is in flight; `scope` names the asker only.
    public func isBusy(_ scope: Scope) -> Bool {
        current != nil
    }

    /// Whether any run is in flight.
    public var isRunning: Bool {
        current != nil
    }

    // MARK: - Actions

    /// The three runs the toolbar, the Overview and the Scope menu start.
    public enum Action: Hashable, Sendable {
        case sync
        case check
        case repair
        /// Set Up = `init`: creates skills.toml and links the agents found (Overview-States "Folder without
        /// skills.toml").
        case setUp
        /// Reinstall from lock = `install --frozen` (Security tab): re-places every locked skill whose folder does
        /// not match skills.lock and never rewrites the lock (`src/commands.rs` `install`, `materialize`).
        case restoreFromLock
    }

    /// Starts `action` from a button: the runner owns the task, the view calls one line (SUI-5).
    public func start(_ action: Action, in store: ScopeStore) {
        Task {
            switch action {
            case .sync: await sync(in: store)
            case .check: await check(in: store)
            case .repair: await repair(in: store)
            case .setUp: await setUp(in: store)
            case .restoreFromLock: await restoreFromLock(in: store)
            }
        }
    }

    /// Sync = `install`: installs exactly what skills.lock pins (brief §6).
    public func sync(in store: ScopeStore) async {
        await run(.install(frozen: false), title: ActionCopy.syncing, outcome: ActionCopy.synced, in: store)
    }

    /// Check = `doctor` without `--fix`: reports, changes nothing.
    public func check(in store: ScopeStore) async {
        await run(.doctor(fix: false), title: ActionCopy.checking, outcome: ActionCopy.checked, in: store)
    }

    /// Repair = `doctor --fix`: links, the git index and the gitignore block; downloads nothing.
    public func repair(in store: ScopeStore) async {
        await run(.doctor(fix: true), title: ActionCopy.repairing, outcome: ActionCopy.repaired, in: store)
    }

    /// Set Up = `init`: writes skills.toml in the scope's folder; downloads nothing.
    public func setUp(in store: ScopeStore) async {
        await run(.initialize, title: ActionCopy.settingUp, outcome: ActionCopy.setUp, in: store)
    }

    /// Reinstall from lock = `install --frozen`: puts back the locked files of every skill whose folder differs
    /// from skills.lock or is missing; fails, changing nothing, when the lock is out of date with skills.toml.
    public func restoreFromLock(in store: ScopeStore) async {
        await run(.install(frozen: true), title: ActionCopy.restoring, outcome: ActionCopy.restored, in: store)
    }

    /// Runs `command` in `store`'s scope with a live transcript, records it, shows its outcome and asks the store
    /// for its targeted refresh. One run at a time in the whole app: a second call while `current` is set does
    /// nothing, because the toolbar is disabled meanwhile.
    public func run(
        _ command: Invocation.Command, title: String, outcome outcomeText: @escaping @Sendable (String) -> String,
        in store: ScopeStore
    ) async {
        guard current == nil else { return }
        failedRun = FailedRun(command: command, title: title, outcome: outcomeText, store: store)
        let invocation: Invocation
        do {
            invocation = try Invocation(command, in: store.scope, capabilities: store.capabilities)
        } catch {
            finish(
                id: UUID(), title: title, command: ActionCopy.unbuilt, startedAt: Date(), duration: .zero,
                status: nil, error: error, transcript: [], outcomeText: outcomeText, store: store)
            return
        }
        let id = UUID()
        let startedAt = Date()
        let client = store.client
        let queue = queue
        let task = Task { [weak self] in
            let onLine: @Sendable (OutputLine) -> Void = { [weak self] line in
                guard let self else { return }
                Task { @MainActor in self.append(line, to: id) }
            }
            let result: Result<RunResult, CLIError>
            do {
                if invocation.isMutation {
                    result = .success(
                        try await queue.enqueue(in: invocation.scope) {
                            try await client.run(invocation, onLine: onLine)
                        })
                } else {
                    result = .success(try await client.run(invocation, onLine: onLine))
                }
            } catch let error as CLIError {
                result = .failure(error)
            } catch is CancellationError {
                result = .failure(.cancelled)
            } catch {
                result = .failure(.launchFailed(String(describing: error)))
            }
            await self?
                .complete(
                    id: id, title: title, invocation: invocation, result: result, outcomeText: outcomeText, store: store
                )
        }
        current = RunningAction(
            id: id, title: title, scope: store.scope, command: invocation.displayCommand, startedAt: startedAt,
            task: task)
        await task.value
    }

    /// Cancels the running command, if any.
    public func cancel() {
        current?.cancel()
    }

    // MARK: - Bookkeeping

    private func append(_ line: OutputLine, to id: UUID) {
        guard current?.id == id else { return }
        current?.lines.append(line)
    }

    private func complete(
        id: UUID, title: String, invocation: Invocation, result: Result<RunResult, CLIError>,
        outcomeText: @escaping @Sendable (String) -> String, store: ScopeStore
    ) async {
        guard let running = current, running.id == id else { return }
        let duration = Duration.seconds(Date().timeIntervalSince(running.startedAt))
        let verdict: CLIError?
        let status: ExitStatus?
        switch result {
        case .success(let run):
            status = run.status
            verdict = Self.verdict(of: run)
        case .failure(let error):
            status = nil
            verdict = error
        }
        finish(
            id: id, title: title, command: running.command, startedAt: running.startedAt, duration: duration,
            status: status, error: verdict, transcript: running.lines, outcomeText: outcomeText, store: store)
        // Always refresh afterwards (ADR §9 #4): a cancelled or failed run may have changed files.
        await store.refreshAfterMutation()
    }

    private func finish(
        id: UUID, title: String, command: String, startedAt: Date, duration: Duration, status: ExitStatus?,
        error: CLIError?, transcript: [OutputLine], outcomeText: (String) -> String, store: ScopeStore
    ) {
        current = nil
        activity.insert(
            ActivityEntry(
                id: id, title: title, command: command, startedAt: startedAt, duration: duration, status: status,
                error: error, transcript: transcript), at: 0)
        if let error {
            let message = ErrorCopy.message(for: error, title: OutcomeCopy.couldNot(title))
            failedRun?.isIntegrity = message.isIntegrity
            outcome = .banner(message, id: id)
        } else {
            failedRun = nil
            outcome = .toast(ToastMessage(id: id, text: outcomeText(ShellCopy.name(of: store.scope))))
        }
    }

    /// The one decoding rule (ADR §4): a command that prints a document succeeded when stdout holds one, whatever
    /// the exit code (`doctor` exits 1 with problems); a mutation without `--json` is judged by its exit.
    static func verdict(of run: RunResult) -> CLIError? {
        if run.invocation.expectsDocument, !run.stdout.isEmpty {
            return nil
        }
        return run.failure()
    }
}
