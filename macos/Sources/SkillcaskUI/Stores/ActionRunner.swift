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
/// (`install --frozen`). Add, update, remove and adopt run from their sheets through `SheetRun`, which calls
/// `run(_:title:outcome:in:from:)` with `.sheet`: the same bookkeeping applies, but the progress and a failure stay
/// in the sheet (S11) instead of the list header and banner.
@MainActor @Observable public final class ActionRunner {
    /// Where a run was started, which decides where its progress and failure show (S11): the list header and the
    /// banner for the toolbar, menus and Overview; inside the sheet for a sheet's run.
    public enum Origin: Hashable, Sendable {
        case window
        case sheet
    }

    /// How a run ended, for the one that started it (`SheetRun`).
    public enum RunEnd: Hashable, Sendable {
        case succeeded
        /// The failure as the banner would word it, `Cancelled.` included.
        case failed(UserMessage)
    }

    /// A command in flight: what the list header and the Activity drawer show.
    public struct RunningAction: Identifiable {
        public let id: UUID
        /// "Syncing…", from `ActionCopy`.
        public let title: String
        public let scope: Scope
        /// `skillcask install`, for the Activity drawer.
        public let command: String
        public let startedAt: Date
        /// `.sheet`: the list header leaves the progress to the sheet.
        public let origin: Origin
        public fileprivate(set) var lines: [OutputLine] = []
        fileprivate let task: Task<RunEnd, Never>?

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
        let failure: String?
        /// The toast text, from the scope name and the transcript (`run`'s `report`, else its `outcome`).
        let report: @Sendable (String, [OutputLine]) -> String
        /// Whether the first run toasted; Retry ends the same way.
        let announce: Bool
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
    /// network failures alone (`FailureBanner.showsRetry`). An integrity failure is never re-run, even if
    /// something calls this anyway: the failed run stays recorded but marked, and the call returns nil. It also
    /// returns nil when nothing has failed since the last success, when the scope's store is gone, or while another
    /// run is in flight; otherwise it returns the new run's task.
    @discardableResult public func retry() -> Task<Void, Never>? {
        guard let failedRun, !failedRun.isIntegrity, let store = failedRun.store, current == nil else { return nil }
        outcome = nil
        return Task {
            await run(
                failedRun.command, title: failedRun.title, failure: failedRun.failure, outcome: { _ in "" },
                report: failedRun.report, in: store, announce: failedRun.announce)
        }
    }

    /// Previews: shows `title` as a run in flight in `scope`, with no child process behind it.
    func preloadRunning(title: String, in scope: Scope, from origin: Origin = .window) {
        current = RunningAction(
            id: UUID(), title: title, scope: scope, command: "", startedAt: Date(), origin: origin, task: nil)
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
        await run(
            .install(frozen: false), title: ActionCopy.syncing, failure: ActionCopy.couldNotSync,
            outcome: ActionCopy.synced,
            in: store)
    }

    /// Check = `doctor` without `--fix`: reports, changes nothing.
    public func check(in store: ScopeStore) async {
        await run(
            .doctor(fix: false), title: ActionCopy.checking, failure: ActionCopy.couldNotCheck,
            outcome: ActionCopy.checked,
            in: store)
    }

    /// Repair = `doctor --fix`: links, the git index and the gitignore block; downloads nothing.
    public func repair(in store: ScopeStore) async {
        await run(
            .doctor(fix: true), title: ActionCopy.repairing, failure: ActionCopy.couldNotRepair,
            outcome: ActionCopy.repaired,
            in: store)
    }

    /// Set Up = `init`: writes skills.toml in the scope's folder; downloads nothing.
    public func setUp(in store: ScopeStore) async {
        await run(
            .initialize, title: ActionCopy.settingUp, failure: ActionCopy.couldNotSetUp, outcome: ActionCopy.setUp,
            in: store)
    }

    /// Reinstall from lock = `install --frozen`: puts back the locked files of every skill whose folder differs
    /// from skills.lock or is missing; fails, changing nothing, when the lock is out of date with skills.toml.
    public func restoreFromLock(in store: ScopeStore) async {
        await run(
            .install(frozen: true), title: ActionCopy.restoring, failure: ActionCopy.couldNotRestore,
            outcome: ActionCopy.restored,
            in: store)
    }

    /// Runs `command` in `store`'s scope with a live transcript, records it, shows its outcome and asks the store
    /// for its targeted refresh. One run at a time in the whole app: a second call while `current` is set does
    /// nothing and returns nil, because the toolbar is disabled meanwhile. Success is a toast unless `announce` is
    /// false (a batch item: the batch shows one summary through `announce(_:)`); a failure is the banner for
    /// `.window` and only the returned `.failed` for `.sheet`, which shows it in place. A sheet's run never touches
    /// the window's banner or its Retry. Cancelling the calling task cancels the run. `failure` is the failure's
    /// title as Copy words it ("Couldn’t sync."); nil falls back to `OutcomeCopy.couldNot(title)` for callers not
    /// yet migrated (that reads "Couldn’t Syncing…." for a progressive title, so every caller should pass one).
    @discardableResult public func run(
        _ command: Invocation.Command, title: String, failure: String? = nil,
        outcome outcomeText: @escaping @Sendable (String) -> String,
        report: (@Sendable (_ scope: String, _ transcript: [OutputLine]) -> String)? = nil, in store: ScopeStore,
        from origin: Origin = .window,
        announce: Bool = true
    ) async -> RunEnd? {
        guard current == nil else { return nil }
        let failureTitle = failure ?? OutcomeCopy.couldNot(title)
        let report: @Sendable (String, [OutputLine]) -> String = report ?? { scope, _ in outcomeText(scope) }
        if origin == .window {
            failedRun = FailedRun(
                command: command, title: title, failure: failure, report: report, announce: announce, store: store)
        }
        let invocation: Invocation
        do {
            invocation = try Invocation(command, in: store.scope, capabilities: store.capabilities)
        } catch {
            return finish(
                id: UUID(), title: title, failure: failureTitle, command: ActionCopy.unbuilt, startedAt: Date(),
                duration: .zero, status: nil, error: error, transcript: [], outcomeText: report, origin: origin,
                announce: announce, store: store)
        }
        let id = UUID()
        let startedAt = Date()
        let client = store.client
        let queue = queue
        let task = Task { [weak self] () -> RunEnd in
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
            guard let self else {
                return .failed(ErrorCopy.message(for: .cancelled, title: failureTitle))
            }
            return await complete(
                id: id, title: title, failure: failureTitle, invocation: invocation, result: result,
                outcomeText: report, origin: origin,
                announce: announce, store: store)
        }
        current = RunningAction(
            id: id, title: title, scope: store.scope, command: invocation.displayCommand, startedAt: startedAt,
            origin: origin, task: task)
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// The one toast of a batch (Adopt All: "Adopted 9 skills"), after its items ran with `announce: false`.
    public func announce(_ text: String) {
        outcome = .toast(ToastMessage(id: UUID(), text: text))
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
        id: UUID, title: String, failure: String, invocation: Invocation, result: Result<RunResult, CLIError>,
        outcomeText: @escaping @Sendable (String, [OutputLine]) -> String, origin: Origin, announce: Bool,
        store: ScopeStore
    ) async -> RunEnd {
        guard let running = current, running.id == id else {
            return .failed(ErrorCopy.message(for: .cancelled, title: failure))
        }
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
        let end = finish(
            id: id, title: title, failure: failure, command: running.command, startedAt: running.startedAt,
            duration: duration,
            status: status, error: verdict, transcript: running.lines, outcomeText: outcomeText, origin: origin,
            announce: announce, store: store)
        // Always refresh afterwards (ADR §9 #4): a cancelled or failed run may have changed files. In a task of its
        // own, which does not inherit this one's cancellation: after Cancel the reads must still run.
        await Task { await store.refreshAfterMutation() }.value
        return end
    }

    private func finish(
        id: UUID, title: String, failure: String, command: String, startedAt: Date, duration: Duration,
        status: ExitStatus?,
        error: CLIError?, transcript: [OutputLine], outcomeText: (String, [OutputLine]) -> String, origin: Origin,
        announce: Bool,
        store: ScopeStore
    ) -> RunEnd {
        current = nil
        activity.insert(
            ActivityEntry(
                id: id, title: title, command: command, startedAt: startedAt, duration: duration, status: status,
                error: error, transcript: transcript), at: 0)
        if let error {
            let message = ErrorCopy.message(for: error, title: failure)
            switch origin {
            case .window:
                failedRun?.isIntegrity = message.isIntegrity
                outcome = .banner(message, id: id)
            case .sheet:
                // The sheet shows the message and offers its own retry; the window's banner and Retry stay as they were.
                break
            }
            return .failed(message)
        }
        if origin == .window {
            failedRun = nil
        }
        if announce {
            outcome = .toast(ToastMessage(id: id, text: outcomeText(ShellCopy.name(of: store.scope), transcript)))
        }
        return .succeeded
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
