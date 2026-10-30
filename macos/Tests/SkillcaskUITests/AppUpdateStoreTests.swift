import Foundation
import SkillcaskCore
import SkillcaskUpdates
import Testing

@testable import SkillcaskUI

/// `AppUpdateStore` (D51): feature off without an app version, consent before any automatic check, the 24-hour
/// schedule, the manual check's outcomes and the `SelfCheckGate` the store must never get around.
@MainActor @Suite struct AppUpdateStoreTests {
    /// A clock the tests move; `sleep` advances it by what was asked and stops the loop after `sleeps` naps.
    @MainActor final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var naps: [Duration] = []
        var sleeps = 1

        func sleep(_ duration: Duration) throws {
            naps.append(duration)
            now = now.addingTimeInterval(TimeInterval(duration.components.seconds))
            if naps.count >= sleeps {
                throw CancellationError()
            }
        }
    }

    static let installed = Version(0, 10, 2)
    static let bundled = Locator.Choice.bundled(
        URL(fileURLWithPath: "/Applications/Skillcask.app/Contents/Helpers/skillcask"))
    static let newer = #"{"version":"0.10.2","latest":"0.10.3","newer":true}"#
    static let same = #"{"version":"0.10.2","latest":"0.10.2","newer":false}"#
    static let unknown = #"{"version":"0.10.2","latest":null,"newer":false}"#

    /// In memory: no plist is left behind.
    let suite = MemoryDefaults()!
    let client = FakeCLIClient()
    let clock = Clock()

    func makeStore(
        installed: Version? = AppUpdateStoreTests.installed, state: UpdateState? = nil,
        binary: Locator.Choice? = AppUpdateStoreTests.bundled, cli: Version = AppUpdateStoreTests.installed,
        ready: Bool = true
    ) -> AppUpdateStore {
        if let state {
            UpdateDefaults(suite).save(state)
        }
        let client = client
        let clock = clock
        return AppUpdateStore(
            installed: installed, defaults: UpdateDefaults(suite), now: { clock.now },
            sleep: { try clock.sleep($0) },
            context: {
                ready ? .init(client: client, binary: binary, capabilities: Capabilities(version: cli)) : nil
            })
    }

    func answer(_ json: String) async {
        await client.json(.selfCheck, in: .personal, json)
    }

    // MARK: - Off

    @Test func withoutAnAppVersionNothingShowsOrRuns() async {
        let store = makeStore(installed: nil, state: UpdateState(consent: .granted, latestSeen: Version(9, 0, 0)))
        store.launch()
        store.cliChanged(isReady: true)
        await store.checkIfDue()
        await store.checkForUpdates()
        #expect(!store.isEnabled)
        #expect(store.card == .none)
        #expect(store.knownUpdate == nil)
        #expect(store.schedule == nil)
        #expect(store.alert == nil && store.sheet == nil)
        #expect(await client.invocations.isEmpty)
        #expect(!AppUpdateStore.disabled.isEnabled)
    }

    // MARK: - Consent

    @Test func undecidedAsksAndRunsNothing() async {
        let store = makeStore()
        store.launch()
        store.cliChanged(isReady: true)
        await store.checkIfDue()
        #expect(store.card == .consentPrompt)
        #expect(store.schedule == nil)
        #expect(await client.invocations.isEmpty)
    }

    @Test func notNowIsRememberedAndRunsNothing() async {
        let store = makeStore()
        store.answerConsent(false)
        store.cliChanged(isReady: true)
        await store.checkIfDue()
        #expect(store.card == .none)
        #expect(UpdateDefaults(suite).load().consent == .declined)
        #expect(await client.invocations.isEmpty)
    }

    @Test func checkDailyChecksAtOnceAndShowsTheCard() async {
        await answer(Self.newer)
        clock.sleeps = 1
        let store = makeStore()
        store.answerConsent(true)
        await store.schedule?.value
        #expect(UpdateDefaults(suite).load().consent == .granted)
        #expect(store.card == .available(Version(0, 10, 3)))
        #expect(store.menuTitle == "Update to 0.10.3…")
        #expect(store.alert == nil && store.sheet == nil, "automatic: nothing pops up")
        #expect(await client.commands == [.selfCheck])
    }

    // MARK: - Schedule

    @Test func launchChecksWhenDueThenEvery24Hours() async {
        for _ in 0..<3 {
            await answer(Self.same)
        }
        clock.sleeps = 3
        let store = makeStore(
            state: UpdateState(consent: .granted, lastCheckAt: clock.now.addingTimeInterval(-25 * 3600)))
        store.launch()
        store.cliChanged(isReady: true)
        await store.schedule?.value
        #expect(await client.commands == [.selfCheck, .selfCheck, .selfCheck])
        #expect(clock.naps == [.seconds(86_400), .seconds(86_400), .seconds(86_400)])
    }

    @Test func launchWaitsWhenTheLastCheckIsRecent() async {
        clock.sleeps = 1
        let store = makeStore(state: UpdateState(consent: .granted, lastCheckAt: clock.now.addingTimeInterval(-3600)))
        store.cliChanged(isReady: true)
        await store.schedule?.value
        #expect(await client.invocations.isEmpty)
        #expect(clock.naps == [.seconds(23 * 3600)])
    }

    @Test func noLoopBeforeTheCLIIsReady() async {
        let store = makeStore(state: UpdateState(consent: .granted), ready: false)
        store.cliChanged(isReady: true)
        await store.checkIfDue()
        #expect(store.schedule == nil)
        #expect(await client.invocations.isEmpty)
    }

    @Test func automaticFailuresAreSilentAndWaitAFullDay() async {
        await client.script(
            .selfCheck, in: .personal, .error(.failed(code: .network, message: "offline", hint: nil, stderr: "")))
        clock.sleeps = 1
        let store = makeStore(state: UpdateState(consent: .granted, latestSeen: Version(0, 10, 3)))
        store.cliChanged(isReady: true)
        await store.schedule?.value
        #expect(store.alert == nil && store.sheet == nil)
        #expect(store.card == .available(Version(0, 10, 3)), "the last known version stays")
        #expect(store.state.lastCheckAt == nil)
        #expect(clock.naps == [.seconds(86_400)])
    }

    @Test func switchingOffStopsTheLoop() {
        let store = makeStore(state: UpdateState(consent: .granted, lastCheckAt: clock.now))
        clock.sleeps = 100
        store.cliChanged(isReady: true)
        #expect(store.schedule != nil)
        store.setDailyCheck(false)
        #expect(store.schedule == nil)
        #expect(store.state.consent == .declined)
    }

    @Test func launchClearsAwaitingRelaunch() {
        let store = makeStore(
            state: UpdateState(consent: .declined, latestSeen: Version(0, 10, 3), awaitingRelaunch: true))
        #expect(store.card == .awaitingRelaunch)
        store.launch()
        #expect(store.card == .available(Version(0, 10, 3)))
        #expect(!UpdateDefaults(suite).load().awaitingRelaunch)
    }

    // MARK: - Manual check

    @Test func manualFindOpensTheSheetIgnoringSkipAndThrottle() async {
        await answer(Self.newer)
        let store = makeStore(
            state: UpdateState(consent: .declined, lastCheckAt: clock.now, skippedVersion: Version(0, 10, 3)))
        await store.checkForUpdates()
        #expect(store.sheet?.version == Version(0, 10, 3))
        #expect(store.alert == nil)
        #expect(store.card == .none, "skipped: the card stays hidden")
    }

    @Test func manualUpToDate() async {
        await answer(Self.same)
        let store = makeStore()
        await store.checkForUpdates()
        #expect(store.alert == .upToDate(Self.installed))
        #expect(store.alert?.title == "You’re up to date")
        #expect(store.alert?.message == "Skillcask 0.10.2 is the newest version.")
        #expect(store.sheet == nil)
        #expect(store.state.lastCheckAt == clock.now)
    }

    @Test func manualUnknownLatest() async {
        await answer(Self.unknown)
        let store = makeStore()
        await store.checkForUpdates()
        #expect(store.alert == .unknown)
        #expect(store.alert?.title == "Couldn’t check for updates")
        #expect(store.alert?.offersRetry == true)
    }

    @Test func manualErrorCarriesTheCLILineAndRetries() async {
        await client.script(
            .selfCheck, in: .personal,
            .error(.failed(code: .network, message: "could not reach raw.githubusercontent.com", hint: nil, stderr: ""))
        )
        await answer(Self.same)
        let store = makeStore()
        await store.checkForUpdates()
        guard case .failed(let line) = store.alert else {
            Issue.record("expected a failure alert, got \(String(describing: store.alert))")
            return
        }
        #expect(line.contains("raw.githubusercontent.com"))
        #expect(store.alert?.offersRetry == true)
        await store.retry()
        #expect(store.alert == .upToDate(Self.installed))
    }

    @Test func knownUpdateOpensTheSheetAndChecksInTheBackground() async {
        await answer(Self.newer)
        let store = makeStore(state: UpdateState(consent: .declined, latestSeen: Version(0, 10, 3)))
        #expect(store.menuTitle == "Update to 0.10.3…")
        await store.checkForUpdates()
        #expect(store.sheet?.version == Version(0, 10, 3))
        #expect(await client.commands == [.selfCheck])
        #expect(store.alert == nil)
    }

    @Test func menuTitleWithoutAKnownUpdate() {
        #expect(makeStore().menuTitle == "Check for Updates…")
        #expect(makeStore(state: UpdateState(latestSeen: Self.installed)).menuTitle == "Check for Updates…")
    }

    // MARK: - Gate

    /// B1 of phase 3: a 0.10.1 CLI chosen in Settings would run `skillcask-self-check` from PATH. The store must
    /// never send it `self-check`, manual or automatic.
    @Test func aConfiguredOldCLINeverGetsSelfCheck() async {
        clock.sleeps = 1
        let old = Locator.Choice.configured(URL(fileURLWithPath: "/opt/homebrew/bin/skillcask"))
        let store = makeStore(state: UpdateState(consent: .granted), binary: old, cli: Version(0, 10, 1))
        store.cliChanged(isReady: true)
        await store.schedule?.value
        await store.checkIfDue()
        await store.checkForUpdates()
        #expect(await client.invocations.isEmpty)
        #expect(store.alert == .unsupported(Version(0, 10, 1)))
        #expect(store.alert?.message.contains("too old") == true)
    }

    // MARK: - Card actions

    @Test func hideCardUntilANewerVersion() async {
        let store = makeStore(state: UpdateState(consent: .declined, latestSeen: Version(0, 10, 3)))
        store.hideCard()
        #expect(store.card == .none)
        #expect(store.menuTitle == "Update to 0.10.3…", "the menu item stays")
        clock.now = clock.now.addingTimeInterval(UpdateState.hideInterval)
        #expect(store.card == .available(Version(0, 10, 3)))
    }

    @Test func sheetPresentationHook() {
        let store = makeStore()
        store.presentSheet(for: Version(0, 10, 3))
        #expect(store.isPresenting)
        store.dismissSheet()
        #expect(!store.isPresenting)
        AppUpdateStore.disabled.presentSheet(for: Version(0, 10, 3))
        #expect(AppUpdateStore.disabled.sheet == nil)
    }

    /// The update sheet or alert keeps a scope sheet from stacking on it (`MainWindow` mirrors the flag).
    @Test func anAppUpdatePresentationBlocksScopeSheets() {
        let stores = Boot.fixtures()
        #expect(!stores.app.isPresenting)
        stores.app.isAppUpdatePresenting = true
        #expect(stores.app.isPresenting)
        #expect(!stores.app.request(.addSkill(query: nil)))
        #expect(!stores.updates.isEnabled, "fixtures: the check is off")
    }

    /// B1 of phase 4a: `-appUpdates.consent declined` (smoke) must not become permanent. A read-only layer behind
    /// the store's values stands in for the argument domain: read by `load()`, never written. Not
    /// `register(defaults:)`: the registration domain is process-wide and would leak into parallel tests.
    @Test func launchArgumentsAreNeverPersisted() {
        let defaults = MemoryDefaults(readOnly: [
            UpdateDefaults.Key.consent: "declined", UpdateDefaults.Key.latestSeen: "0.10.3",
        ])!
        let clock = clock
        let store = AppUpdateStore(
            installed: Self.installed, defaults: UpdateDefaults(defaults), now: { clock.now }, context: { nil })
        #expect(store.state.consent == .declined)
        store.launch()
        #expect(defaults.values.isEmpty, "launch writes nothing")
        #expect(store.card == .available(Version(0, 10, 3)))
        store.hideCard()
        #expect(defaults.values[UpdateDefaults.Key.consent] == nil)
        #expect(defaults.values[UpdateDefaults.Key.latestSeen] == nil)
        #expect(defaults.values[UpdateDefaults.Key.hiddenUntil] != nil)
    }

    /// The consent card needs a CLI the gate lets through: none for a configured 0.10.1.
    @Test func noConsentPromptForACLIThatCannotSelfCheck() {
        let old = Locator.Choice.configured(URL(fileURLWithPath: "/opt/homebrew/bin/skillcask"))
        let refused = makeStore(binary: old, cli: Version(0, 10, 1)).card
        let unready = makeStore(ready: false).card
        let bundled = makeStore().card
        #expect(refused == UpdateCard.none)
        #expect(unready == UpdateCard.none)
        #expect(bundled == .consentPrompt)
    }

    /// The loop, an activation and the menu share one request.
    @Test func overlappingChecksShareOneRequest() async {
        let gate = Gate()
        await client.json(.selfCheck, in: .personal, Self.same, gate: gate)
        let store = makeStore(state: UpdateState(consent: .granted))
        let automatic = Task { await store.checkIfDue() }
        await gate.arrived()
        let manual = Task { await store.checkForUpdates() }
        // `isChecking` is set in the same synchronous step that joins the check in flight.
        while !store.isChecking {
            await Task.yield()
        }
        await gate.open()
        await automatic.value
        await manual.value
        #expect(await client.commands == [.selfCheck])
        #expect(store.alert == .upToDate(Self.installed))
    }
}
