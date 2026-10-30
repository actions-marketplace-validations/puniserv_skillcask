import Foundation
import Observation
import SkillcaskCore
import SkillcaskUpdates

/// The app-update check of D51 as the window sees it: the sidebar card, the app menu item, the manual check's alert
/// and the update sheet's presentation. It asks only through `CLIClient.selfCheck(binary:capabilities:)` (the gate
/// decides whether the CLI may be asked at all) and keeps what it learnt in `UpdateDefaults`. The rules are
/// `UpdateDecision` and `UpdateSchedule`; this store only runs them.
///
/// Without an installed version (`swift run`, fixtures, renders) the feature is off: no card, no menu item, no
/// check. With one, nothing runs on its own until consent is granted: then a check on launch once the CLI is ready
/// when the last answer is 24 hours old, and every 24 hours while the app runs; automatic failures stay silent.
@MainActor @Observable public final class AppUpdateStore {
    /// What a check runs with: the ready CLI, where it was found and what it can do.
    public struct Context: Sendable {
        public let client: any CLIClient
        public let binary: Locator.Choice?
        public let capabilities: Capabilities

        public init(client: any CLIClient, binary: Locator.Choice?, capabilities: Capabilities) {
            self.client = client
            self.binary = binary
            self.capabilities = capabilities
        }
    }

    /// The manual check's answer when it is not an update (U4); an update opens the sheet instead.
    public enum Alert: Hashable, Identifiable, Sendable {
        /// `You’re up to date` with the installed version.
        case upToDate(Version)
        /// The CLI answered `latest: null`.
        case unknown
        /// The check failed: the CLI's error line. Try Again · OK.
        case failed(String)
        /// The CLI chosen in Settings predates `self-check`.
        case unsupported(Version)

        public var id: Self { self }

        public var title: String {
            switch self {
            case .upToDate: AppUpdateCopy.upToDateTitle
            case .unknown, .failed, .unsupported: AppUpdateCopy.failedTitle
            }
        }

        public var message: String {
            switch self {
            case .upToDate(let version): AppUpdateCopy.upToDateMessage(version)
            case .unknown: AppUpdateCopy.unknownMessage
            case .failed(let line): line
            case .unsupported(let version): AppUpdateCopy.unsupportedMessage(version)
            }
        }

        /// Try Again is offered where asking again can help.
        public var offersRetry: Bool {
            switch self {
            case .unknown, .failed: true
            case .upToDate, .unsupported: false
            }
        }
    }

    /// The update sheet on screen, for `.sheet(item:)`: one identity per presentation.
    public struct SheetRequest: Identifiable, Hashable, Sendable {
        public let id: UUID
        /// The version the sheet offers (newer than `installed`).
        public let version: Version
    }

    /// The app's own version (`AppVersion.main()`); nil turns everything off.
    public let installed: Version?
    public private(set) var state: UpdateState {
        didSet { defaults.save(state, changedFrom: oldValue) }
    }
    /// A manual check is running: the menu item is disabled meanwhile.
    public private(set) var isChecking = false
    /// The manual check's alert; any button or Esc clears it.
    public var alert: Alert?
    /// The update sheet's presentation (phase 4b draws its body); `presentSheet(for:)` and `dismissSheet()` set it.
    public private(set) var sheet: SheetRequest?

    @ObservationIgnored private let defaults: UpdateDefaults
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void
    @ObservationIgnored private let context: @MainActor () -> Context?
    /// The daily loop while consent is granted and the CLI is ready; internal so tests can await it.
    @ObservationIgnored var schedule: Task<Void, Never>?
    @ObservationIgnored private var scheduleID = UUID()
    /// The check running now: the loop, an activation, the menu and the known-update re-check share it, so they
    /// never send two requests at once.
    @ObservationIgnored private var inFlight: Task<Result<SelfCheckOutcome, CLIError>, Never>?

    /// - Parameters:
    ///   - installed: The app's version; nil (no `.app`, fixtures) turns the feature off.
    ///   - defaults: Where `UpdateState` lives (`appUpdates.*`).
    ///   - now: The clock.
    ///   - sleep: Waits between automatic checks.
    ///   - context: The ready CLI, or nil while it is not.
    public init(
        installed: Version?, defaults: UpdateDefaults, now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        context: @escaping @MainActor () -> Context?
    ) {
        self.installed = installed
        self.defaults = defaults
        self.now = now
        self.sleep = sleep
        self.context = context
        state = defaults.load()
    }

    /// Off: fixtures, previews and every scene given no store.
    public static let disabled = AppUpdateStore(
        installed: nil, defaults: UpdateDefaults(UserDefaults(suiteName: "skillcask.ui.updates.disabled") ?? .standard),
        context: { nil })

    // MARK: - Derived

    /// The feature is on: the app knows its version.
    public var isEnabled: Bool {
        installed != nil
    }

    /// A check can run: the CLI is ready.
    public var isReady: Bool {
        context() != nil
    }

    /// The ready CLI may be asked `self-check` (`SelfCheckGate`): the bundled helper, or a CLI that ships it.
    public var canCheck: Bool {
        context().map { SelfCheckGate.allows(binary: $0.binary, capabilities: $0.capabilities) } ?? false
    }

    /// What the sidebar card slot shows now (`UpdateDecision.card`); no consent prompt for a CLI the gate refuses,
    /// since no daily check could run on it.
    public var card: UpdateCard {
        let card = UpdateDecision.card(installed: installed, state: state, now: now())
        return card == .consentPrompt && !canCheck ? .none : card
    }

    /// The version the menu offers and the sheet opens on, whatever the card hides.
    public var knownUpdate: Version? {
        UpdateDecision.knownUpdate(installed: installed, latest: state.latestSeen)
    }

    /// `Update to X…` when an update is known, else `Check for Updates…`.
    public var menuTitle: String {
        knownUpdate.map(AppUpdateCopy.updateTo) ?? AppUpdateCopy.checkForUpdates
    }

    /// The sheet or the alert is up: `AppStore` refuses its own requests meanwhile.
    public var isPresenting: Bool {
        sheet != nil || alert != nil
    }

    // MARK: - Lifecycle

    /// The launch hook: a new process clears `awaitingRelaunch` (`UpdateDefaults.launched()`).
    public func launch() {
        guard isEnabled else { return }
        state = defaults.launched()
    }

    /// The CLI became ready (or went away): starts the daily loop when consent allows, stops it otherwise.
    public func cliChanged(isReady: Bool) {
        if isReady {
            startSchedule()
        } else {
            stopSchedule()
        }
    }

    /// The app became active (also after a wake): a 24-hour sleep drifts across system sleep, so the check runs
    /// here when it is due, as the loop would.
    public func checkIfDue() async {
        guard isEnabled, context() != nil, UpdateSchedule.shouldCheckAutomatically(state, now: now()) else { return }
        await automaticCheck()
    }

    // MARK: - Consent

    /// The consent card's `Check Daily` (true) or `Not Now` (false). Granting starts the loop, which checks at once
    /// when due.
    public func answerConsent(_ granted: Bool) {
        setDailyCheck(granted)
    }

    /// Settings › Updates' switch (phase 4b) and the consent card.
    public func setDailyCheck(_ on: Bool) {
        state.consent = on ? .granted : .declined
        if on {
            startSchedule()
        } else {
            stopSchedule()
        }
    }

    // MARK: - Card and sheet actions

    /// × on the card: hides the version it shows until a newer one or 7 days.
    public func hideCard() {
        guard case .available(let version) = card else { return }
        state.hide(version, at: now())
    }

    /// `Skip This Version`.
    public func skip(_ version: Version) {
        state.skip(version)
    }

    /// `Remind Me Tomorrow`.
    public func remindTomorrow() {
        state.remindTomorrow(at: now())
    }

    /// `Copy Command` / `Copy and Open Terminal` for a Homebrew install: the waiting card until the next launch.
    public func copiedCommand() {
        state.copiedCommand()
    }

    /// Settings › Updates `Reset`.
    public func resetSkipped() {
        state.resetSkipped()
    }

    /// Opens the update sheet on `version` (the card's `See What’s New…`, `Update to X…`, a manual check's find).
    public func presentSheet(for version: Version) {
        guard isEnabled else { return }
        sheet = SheetRequest(id: UUID(), version: version)
    }

    /// Closes the sheet (Esc, a footer button). No state changes here: the button that closes says what it did.
    public func dismissSheet() {
        sheet = nil
    }

    // MARK: - Checks

    /// "Check for Updates…" / "Update to X…" (U4): ignores the schedule, skip, × and Remind. A known update opens the
    /// sheet at once and checks again in the background; otherwise the answer opens the sheet or an alert.
    public func checkForUpdates() async {
        guard let installed, !isChecking else { return }
        if let known = knownUpdate {
            presentSheet(for: known)
            await automaticCheck()
            return
        }
        isChecking = true
        defer { isChecking = false }
        let result = await run()
        record(result)
        switch result {
        case .success(.checked(let document)):
            switch UpdateDecision.manual(installed: installed, document: document) {
            case .available(let version): presentSheet(for: version)
            case .upToDate(let version): alert = .upToDate(version)
            case .unknown: alert = .unknown
            }
        case .success(.unsupported):
            alert = .unsupported(context()?.capabilities.version ?? installed)
        case .failure(.cancelled):
            break
        case .failure(let error):
            alert = .failed(AppUpdateCopy.failedMessage(error))
        }
    }

    /// The alert's Try Again.
    public func retry() async {
        alert = nil
        await checkForUpdates()
    }

    /// One automatic check: the answer is recorded, nothing is shown, failures change nothing.
    func automaticCheck() async {
        record(await run())
    }

    /// Joins the check in flight, or starts one.
    private func run() async -> Result<SelfCheckOutcome, CLIError> {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { await self.selfCheck() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func selfCheck() async -> Result<SelfCheckOutcome, CLIError> {
        guard let context = context() else { return .failure(.binaryMissing(searched: [])) }
        do {
            return .success(
                try await context.client.selfCheck(binary: context.binary, capabilities: context.capabilities))
        } catch {
            return .failure(error)
        }
    }

    private func record(_ result: Result<SelfCheckOutcome, CLIError>) {
        state.record(result, at: now())
    }

    // MARK: - Schedule

    /// Starts the daily loop once: on, consented, the CLI ready and no loop running.
    func startSchedule() {
        guard isEnabled, state.consent == .granted, schedule == nil, context() != nil else { return }
        let id = UUID()
        scheduleID = id
        schedule = Task { [weak self] in
            await self?.runSchedule()
            if self?.scheduleID == id {
                self?.schedule = nil
            }
        }
    }

    private func stopSchedule() {
        schedule?.cancel()
        schedule = nil
        scheduleID = UUID()
    }

    /// Checks when due, then sleeps until the next check is due; after a failure (still due) a full interval, so
    /// an offline machine is asked once a day, not in a loop.
    private func runSchedule() async {
        while !Task.isCancelled, state.consent == .granted {
            if UpdateSchedule.shouldCheckAutomatically(state, now: now()) {
                await automaticCheck()
            }
            let current = now()
            let next = UpdateSchedule.nextCheck(lastCheckAt: state.lastCheckAt, now: current)
            let wait = next > current ? next.timeIntervalSince(current) : UpdateSchedule.interval
            do {
                try await sleep(.seconds(wait))
            } catch {
                return
            }
        }
    }
}
