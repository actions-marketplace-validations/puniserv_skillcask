import Foundation
import SkillcaskCore
import SkillcaskDomain
import Testing

@testable import SkillcaskUI

/// S15 (Activity board): every run of the session is recorded (window, sheet, each batch item), bounded, its exit
/// said in one word; Details opens the drawer at the run; Copy copies what the row shows; nothing secret is kept.
@Suite @MainActor struct ActivityTests {
    let client = FakeCLIClient()
    let scope = Scope.project(URL(fileURLWithPath: "/tmp/activity-tests"))
    let capabilities = Capabilities(version: Capabilities.minimum)

    func store() -> ScopeStore {
        let store = ScopeStore(scope: scope, client: client, capabilities: capabilities) { _ in SkillText.parse("") }
        store.preload(snapshot: DesignFixtures.api)
        return store
    }

    func adopt(_ skill: String) -> Invocation.Command {
        .add(spec: "github:acme/\(skill)", repository: nil, adopt: true, rename: [:], skills: [])
    }

    func entry(
        status: SkillcaskCore.ExitStatus? = .exited(0), error: CLIError? = nil, transcript: [OutputLine] = [],
        expectsDocument: Bool = false, environment: [String] = []
    ) -> ActionRunner.ActivityEntry {
        ActionRunner.ActivityEntry(
            title: "Syncing with skills.lock…", headline: "Synced api", command: "skillcask install", scope: scope,
            startedAt: Date(timeIntervalSince1970: 0), duration: .milliseconds(3200), status: status, error: error,
            transcript: transcript, isMutation: true, expectsDocument: expectsDocument,
            environmentOverrides: environment)
    }

    // MARK: - Recording

    @Test(.timeLimit(.minutes(1))) func aWindowRunIsRecordedWithItsCommandAndEnvironmentNames() async {
        await client.environment(["HTTPS_PROXY"])
        await client.lines(.install(frozen: false), in: scope, ["Installing pdf 1.2.0 (packagist)…"])
        let store = store()
        let runner = ActionRunner(queue: MutationQueue())
        await runner.sync(in: store)
        let run = runner.activity.first
        #expect(runner.activity.count == 1)
        #expect(run?.title == "Syncing with skills.lock…")
        #expect(run?.headline == "Synced activity-tests")
        #expect(run?.command == "skillcask install")
        #expect(run?.ending == .ok && run?.isMutation == true && run?.mayHaveWrittenLock == true)
        #expect(run?.environmentOverrides == ["HTTPS_PROXY"])
        #expect(run?.transcript == [.stdout("Installing pdf 1.2.0 (packagist)…")])
        #expect(runner.isActivityShown == false, "a run never opens the drawer on its own")
    }

    @Test(.timeLimit(.minutes(1))) func aFailedWindowRunIsHeadlinedByItsFailure() async {
        await client.lines(.install(frozen: false), in: scope, [], exit: 2)
        let store = store()
        let runner = ActionRunner(queue: MutationQueue())
        await runner.sync(in: store)
        guard let run = runner.activity.first else {
            Issue.record("the failed sync was not recorded")
            return
        }
        #expect(ActivityCopy.headline(of: run) == "Couldn’t sync")
        #expect(ActivityCopy.word(for: run.ending) == "sign-in needed")
        #expect(runner.isActivityShown == false, "a failure opens the drawer only through Details")
    }

    @Test(.timeLimit(.minutes(1))) func aSheetRunIsRecorded() async {
        let update = Invocation.Command.update(packages: ["anthropics/skills"])
        await client.lines(update, in: scope, ["Updating pdf 1.2.0 → 1.4.0 (packagist)…"])
        let runner = ActionRunner(queue: MutationQueue())
        await SheetRun()
            .start(
                update, title: "Updating pdf…", outcome: { "Updated pdf in \($0)" }, in: store(), runner: runner,
                onSuccess: {})?
            .value
        #expect(runner.activity.map(\.headline) == ["Updated pdf in activity-tests"])
        #expect(runner.activity.first?.command == "skillcask update -- anthropics/skills")
    }

    @Test(.timeLimit(.minutes(1))) func eachBatchItemIsARow() async {
        for skill in ["a", "b"] {
            await client.lines(adopt(skill), in: scope, ["Adopted \(skill)"])
        }
        let runner = ActionRunner(queue: MutationQueue())
        await SheetRun()
            .startBatch(
                ["a", "b"], title: "Adopting 2 skills…", command: adopt, itemTitle: { "Adopting \($0)…" },
                summary: { done, scope in "Adopted \(done) skills in \(scope)" }, in: store(), runner: runner,
                onSuccess: {})?
            .value
        #expect(runner.activity.count == 2)
        #expect(runner.activity.map { ActivityCopy.headline(of: $0) } == ["Adopting b", "Adopting a"])
        #expect(runner.activity.allSatisfy { $0.ending == .ok })
    }

    // MARK: - Exit words

    @Test(.timeLimit(.minutes(1))) func aDocumentWithExitOneIsFindingsNotAFailure() async {
        let doctor = #"{"ok":false,"passed":[],"problems":["link: pdf missing"],"fixed":[],"warnings":[]}"#
        await client.json(.doctor(fix: false), in: scope, doctor, exit: 1)
        let store = store()
        let runner = ActionRunner(queue: MutationQueue())
        await runner.check(in: store)
        let run = runner.activity.first
        #expect(run?.ending == .findings)
        #expect(run.map { ActivityCopy.word(for: $0.ending) } == "needs attention")
        #expect(run.map { ActivityCopy.severity(for: $0.ending) } == .warning)
    }

    @Test func exitWords() {
        let failed = { (code: ExitCode, message: String) -> CLIError in
            .failed(code: code, message: message, hint: nil, stderr: "")
        }
        let cases: [(ActionRunner.ActivityEntry, String, Severity)] = [
            (entry(), "ok", .ok),
            (entry(status: .exited(1), expectsDocument: true), "needs attention", .warning),
            (entry(status: .exited(1), error: failed(.problem, "skills.toml is invalid")), "failed", .error),
            (entry(status: .exited(2), error: failed(.signIn, "needs you to sign in")), "sign-in needed", .error),
            (entry(status: .exited(3), error: failed(.network, "unreachable")), "network error", .error),
            (entry(status: .exited(4), error: failed(.integrity, "hash mismatch")), "hash mismatch", .error),
            (entry(status: .exited(101), error: failed(.other(101), "panicked")), "exit 101", .error),
            (entry(status: nil, error: .cancelled), "cancelled", .neutral),
            (
                entry(status: .exited(1), error: failed(.problem, "github:evil/x is not an allowed source")),
                "refused by policy", .warning
            ),
            (entry(status: nil, error: .invalidInvocation("update needs package names")), "not run", .neutral),
            (entry(status: .exited(0), error: .noDocument), "unreadable output", .error),
        ]
        for (run, word, severity) in cases {
            #expect(ActivityCopy.word(for: run.ending) == word)
            #expect(ActivityCopy.severity(for: run.ending) == severity, "\(word)")
        }
    }

    @Test(.timeLimit(.minutes(1))) func aCancelledRunSaysCancelled() async {
        let gate = Gate()
        await client.lines(.install(frozen: false), in: scope, [], gate: gate)
        let store = store()
        let runner = ActionRunner(queue: MutationQueue())
        let task = Task { await runner.sync(in: store) }
        await gate.arrived()
        runner.cancel()
        await gate.open()
        await task.value
        #expect(runner.activity.first?.ending == .cancelled)
    }

    @Test func timingAndHeadlines() {
        let start = Date(timeIntervalSince1970: 14 * 3600 + 2 * 60)
        #expect(ActivityCopy.timing(.milliseconds(3200), startedAt: start, timeZone: .gmt) == "3.2 s · 14:02")
        #expect(ActivityCopy.duration(.seconds(72)) == "1 min 12 s")
        #expect(ActivityCopy.duration(.milliseconds(400)) == "0.4 s")
        #expect(ActivityCopy.session(runs: 6) == "this session · 6 runs")
        #expect(ActivityCopy.session(runs: 1) == "this session · 1 run")
        #expect(ActivityCopy.session(runs: 6, kept: 6) == "this session · 6 runs")
        #expect(ActivityCopy.session(runs: 250, kept: 100) == "this session · 250 runs · last 100 kept")
    }

    // MARK: - Bounds

    @Test(.timeLimit(.minutes(1))) func theSessionKeepsTheNewestRuns() async {
        let store = store()
        let runner = ActionRunner(queue: MutationQueue())
        // An update without a package name cannot be built: recorded at once, no child, no refresh.
        for index in 0...ActionRunner.ActivityEntry.limit {
            await runner.run(.update(packages: [""]), title: "Run \(index)", outcome: { $0 }, in: store)
        }
        #expect(runner.activity.count == ActionRunner.ActivityEntry.limit)
        #expect(runner.sessionRunCount == ActionRunner.ActivityEntry.limit + 1, "the header counts the whole session")
        #expect(runner.activity.first?.title == "Run \(ActionRunner.ActivityEntry.limit)")
        #expect(runner.activity.last?.title == "Run 1")
        #expect(runner.activity.first?.ending == .notRun)
    }

    @Test func aTranscriptKeepsItsLastLinesClipped() {
        let limit = ActionRunner.ActivityEntry.transcriptLimit
        let lines = (0..<(limit + 5)).map { OutputLine.stdout("line \($0)") }
        let long = String(repeating: "x", count: ActionRunner.ActivityEntry.lineLimit + 10)
        let run = entry(transcript: lines + [.stderr(long)])
        #expect(run.transcript.count == limit)
        #expect(run.omittedLines == 6)
        #expect(run.transcript.first == .stdout("line 6"))
        #expect(run.transcript.last == .stderr(String(long.prefix(ActionRunner.ActivityEntry.lineLimit)) + "…"))
        #expect(ActivityCopy.transcriptLines(of: run).first == "… 6 earlier lines not kept")
    }

    @Test func aTranscriptKeepsAtMostItsCharacterBudget() {
        let limit = ActionRunner.ActivityEntry.characterLimit
        let line = String(repeating: "y", count: ActionRunner.ActivityEntry.lineLimit)
        let count = ActionRunner.ActivityEntry.transcriptLimit
        let run = entry(transcript: (0..<count).map { _ in OutputLine.stdout(line) })
        #expect(run.transcript.count == limit / line.count)
        #expect(run.transcript.map(\.text.count).reduce(0, +) <= limit)
        #expect(run.omittedLines == count - limit / line.count)
    }

    @Test(.timeLimit(.minutes(1))) func aLongLiveTranscriptIsBounded() async {
        let limit = ActionRunner.ActivityEntry.transcriptLimit
        await client.lines(.install(frozen: false), in: scope, (0..<(limit + 300)).map { "line \($0)" })
        let store = store()
        let runner = ActionRunner(queue: MutationQueue())
        await runner.sync(in: store)
        let run = runner.activity.first
        #expect(run?.transcript.count == limit)
        #expect(run?.omittedLines == 300)
        #expect(run?.transcript.last == .stdout("line \(limit + 299)"))
    }

    // MARK: - Reads

    func recordingStore(into runner: ActionRunner, settings: SettingsStore? = nil) -> ScopeStore {
        let store = ScopeStore(scope: scope, client: client, capabilities: capabilities, settings: settings) { _ in
            SkillText.parse("")
        }
        store.recordActivity = { [weak runner] in runner?.record($0) }
        return store
    }

    func scriptTrio(statusExit: Int32 = 0) async {
        await client.json(.status, in: scope, ScopeStoreTests.status([("pdf", "1.4.0")]), exit: statusExit)
        await client.json(.audit, in: scope, ScopeStoreTests.emptyAudit)
        await client.json(.doctor(fix: false), in: scope, ScopeStoreTests.cleanDoctor)
    }

    static let emptyOutdated = #"{"packages":[],"behind":[]}"#

    @Test(.timeLimit(.minutes(1))) func openingAScopeIsRecordedAsOneRow() async {
        await client.environment(["HTTPS_PROXY"])
        await scriptTrio()
        let runner = ActionRunner(queue: MutationQueue())
        let store = recordingStore(into: runner)
        await store.refreshIfStale()
        #expect(runner.activity.count == 1)
        let run = runner.activity.first
        #expect(run?.headline == "Opened activity-tests" && run?.ending == .ok)
        #expect(
            run.map(ActivityCopy.commands(of:)) == [
                "skillcask status --json", "skillcask audit --json", "skillcask doctor --json",
            ])
        #expect(run?.environmentOverrides == ["HTTPS_PROXY"] && run?.mayHaveWrittenLock == false)
        await store.refreshIfStale()
        #expect(runner.activity.count == 1, "a fresh scope is not read again, so nothing is recorded")
    }

    @Test(.timeLimit(.minutes(1))) func refreshIsRecordedAndAFailureSaysWhy() async {
        await client.lines(.status, in: scope, [], exit: 3)
        await client.json(.audit, in: scope, ScopeStoreTests.emptyAudit)
        await client.json(.doctor(fix: false), in: scope, ScopeStoreTests.cleanDoctor)
        let runner = ActionRunner(queue: MutationQueue())
        await recordingStore(into: runner).refresh()
        let run = runner.activity.first
        #expect(run.map(ActivityCopy.headline(of:)) == "Couldn’t refresh activity-tests")
        #expect(run.map { ActivityCopy.word(for: $0.ending) } == "network error")
    }

    @Test(.timeLimit(.minutes(1))) func switchingScopesMidReadRecordsNothing() async {
        let gate = Gate()
        await client.json(.status, in: scope, ScopeStoreTests.status([("pdf", "1.4.0")]), gate: gate)
        await client.json(.audit, in: scope, ScopeStoreTests.emptyAudit)
        await client.json(.doctor(fix: false), in: scope, ScopeStoreTests.cleanDoctor)
        let runner = ActionRunner(queue: MutationQueue())
        let store = recordingStore(into: runner)
        // The list's `.task(id: scope)` is cancelled when another scope is selected.
        let task = Task { await store.refreshIfStale() }
        await gate.arrived()
        task.cancel()
        await gate.open()
        await task.value
        #expect(runner.activity.isEmpty && runner.sessionRunCount == 0)
    }

    @Test(.timeLimit(.minutes(1))) func aReadTakesTheFirstFailureOfTheTrio() async {
        await client.json(.status, in: scope, ScopeStoreTests.status([("pdf", "1.4.0")]))
        await client.lines(.audit, in: scope, [], exit: 5)
        await client.lines(.doctor(fix: false), in: scope, [], exit: 3)
        let runner = ActionRunner(queue: MutationQueue())
        await recordingStore(into: runner).refresh()
        let run = runner.activity.first
        #expect(run?.status == .exited(5))
        #expect(run.map { ActivityCopy.word(for: $0.ending) } == "file error")
        #expect(run.map(ActivityCopy.headline(of:)) == "Couldn’t refresh activity-tests")
    }

    @Test(.timeLimit(.minutes(1))) func closingTheReviewSheetMidLoadStillRecords() async {
        let gate = Gate()
        await client.json(
            .diff(package: "anthropics/skills"), in: scope, DesignFixtures.text("diff.pdf", "txt"), gate: gate)
        let runner = ActionRunner(queue: MutationQueue())
        let store = recordingStore(into: runner)
        store.preload(snapshot: DesignFixtures.api)
        let review = ReviewStore(package: "pdf", offeredVersion: "1.4.0", store: store)
        let task = Task { await review.load() }
        await gate.arrived()
        task.cancel()
        await gate.open()
        await task.value
        #expect(runner.activity.count == 1, "closing the sheet is the user's act")
        #expect(runner.activity.first?.ending == .cancelled)
    }

    @Test(.timeLimit(.minutes(1))) func checkForUpdatesIsRecorded() async {
        await client.json(.outdated, in: scope, Self.emptyOutdated)
        let runner = ActionRunner(queue: MutationQueue())
        await recordingStore(into: runner).checkUpdates()
        #expect(runner.activity.map(\.headline) == ["Checked for updates"])
        #expect(runner.activity.first?.command == "skillcask outdated --json")
    }

    @Test(.timeLimit(.minutes(1))) func theReviewSheetsDiffIsRecorded() async {
        await client.json(.diff(package: "anthropics/skills"), in: scope, DesignFixtures.text("diff.pdf", "txt"))
        let runner = ActionRunner(queue: MutationQueue())
        let store = recordingStore(into: runner)
        store.preload(snapshot: DesignFixtures.api)
        let review = ReviewStore(package: "pdf", offeredVersion: "1.4.0", store: store)
        await review.load()
        #expect(runner.activity.map(\.headline) == ["Reviewed changes for pdf 1.2.0 → 1.4.0"])
        #expect(runner.activity.first?.command == "skillcask diff -- anthropics/skills")
        #expect(runner.activity.first?.ending == .ok && runner.activity.first?.mayHaveWrittenLock == false)
    }

    @Test(.timeLimit(.minutes(1))) func aMutationsOwnRefreshIsNotRecorded() async {
        await client.lines(.install(frozen: false), in: scope, ["Installing pdf"])
        await scriptTrio()
        await client.json(.outdated, in: scope, Self.emptyOutdated)
        await client.json(.outdated, in: scope, Self.emptyOutdated)
        let runner = ActionRunner(queue: MutationQueue())
        let store = recordingStore(into: runner)
        await store.checkUpdates()
        await runner.sync(in: store)
        #expect(await client.commands.contains(.status), "the sync's refresh ran")
        #expect(await client.commands.filter { $0 == .outdated }.count == 2, "and re-checked updates")
        #expect(runner.activity.map(\.title) == ["Syncing with skills.lock…", "Checked for updates"])
    }

    @Test(.timeLimit(.minutes(1))) func checkOnOpenFromSettingsIsNotRecorded() async {
        let suite = "activity-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.checkUpdatesOnOpen = true
        await scriptTrio()
        await client.json(.outdated, in: scope, Self.emptyOutdated)
        let runner = ActionRunner(queue: MutationQueue())
        await recordingStore(into: runner, settings: settings).refreshIfStale()
        #expect(await client.commands.contains(.outdated), "the open checked for updates")
        #expect(runner.activity.map(\.headline) == ["Opened activity-tests"])
    }

    @Test func appStoreHandsItsSinkToEveryScopeStore() {
        let stores = Boot.fixtures()
        stores.app.store(for: Boot.apiScope)?.recordActivity?(entry())
        #expect(stores.runner.activity.count == 1)
    }

    // MARK: - Details

    @Test(.timeLimit(.minutes(1))) func detailsOpenTheDrawerAtTheRun() async {
        await client.lines(.install(frozen: false), in: scope, [])
        let store = store()
        let runner = ActionRunner(queue: MutationQueue())
        await runner.sync(in: store)
        guard let toast = runner.toast else {
            Issue.record("sync did not toast")
            return
        }
        runner.consumeDetailsRequest()
        #expect(!runner.isActivityShown, "nothing asked: the drawer stays hidden")
        runner.showDetails(of: toast.id)
        runner.consumeDetailsRequest()
        #expect(runner.detailsRequest == nil)
        #expect(runner.isActivityShown)
        #expect(runner.activityFocus == toast.id)
        #expect(runner.expandedActivity == [toast.id])
        runner.clearActivityFocus()
        #expect(runner.activityFocus == nil)
    }

    @Test func detailsOfAnUnknownRunOpenTheDrawerWithoutScrolling() {
        let runner = ActionRunner(queue: MutationQueue())
        runner.preloadActivity([entry()], shown: false)
        // A batch's summary toast carries a fresh id that names no run.
        runner.announce("Adopted 2 skills in api")
        if let toast = runner.toast {
            runner.showDetails(of: toast.id)
        }
        runner.consumeDetailsRequest()
        #expect(runner.isActivityShown)
        #expect(runner.activityFocus == nil && runner.expandedActivity.isEmpty)
        #expect(runner.detailsRequest == nil)
    }

    @Test func toggles() {
        let runner = ActionRunner(queue: MutationQueue())
        let run = entry()
        runner.preloadActivity([run], shown: false)
        runner.toggleActivity()
        #expect(runner.isActivityShown)
        runner.toggleActivity()
        #expect(!runner.isActivityShown)
        runner.toggleExpanded(run.id)
        #expect(runner.expandedActivity == [run.id])
        runner.toggleExpanded(run.id)
        #expect(runner.expandedActivity.isEmpty)
    }

    // MARK: - Copy

    @Test func copyIsExactlyTheExpandedText() {
        let run = entry(
            transcript: [.stdout("Installing pdf"), .stderr("warning: slow")], environment: ["HTTPS_PROXY"])
        let shown = ActivityCopy.commandLines(of: run) + ActivityCopy.transcriptLines(of: run)
        #expect(
            shown == [
                "skillcask install", "Environment from Settings: HTTPS_PROXY=••••", "Installing pdf", "warning: slow",
            ])
        #expect(ActivityCopy.copyText(of: run) == shown.joined(separator: "\n"))
        let quiet = entry()
        #expect(ActivityCopy.copyText(of: quiet) == "skillcask install\nNo output.")
        #expect(
            ActivityCopy.copyAllText(of: [quiet], timeZone: .gmt)
                == "Synced api · ok · 3.2 s · 00:00\nskillcask install\nNo output.")
    }

    // MARK: - Secrets

    @Test(.timeLimit(.minutes(1))) func noSecretReachesTheRecord() async {
        let secret = "pa55-ghp_0123456789"
        await client.environment(["HTTPS_PROXY"])
        await client.lines(.install(frozen: false), in: scope, ["Installing pdf"])
        let store = store()
        let runner = ActionRunner(queue: MutationQueue())
        await runner.sync(in: store)
        let text = ActivityCopy.copyAllText(of: runner.activity) + String(describing: runner.activity)
        #expect(text.contains("HTTPS_PROXY=••••"))
        #expect(!text.contains(secret))
        // The token of `auth set` goes to stdin, which neither the command line nor any description shows.
        let auth = try? Invocation(
            .authSet(host: "github.com", username: nil), in: scope, capabilities: capabilities, stdin: .text(secret))
        #expect(auth.map { !$0.displayCommand.contains(secret) && !String(describing: $0).contains(secret) } == true)
        #expect(ActivityCopy.environment(["HTTPS_PROXY", "SKILLCASK_CACHE_DIR"]).contains("=••••, SKILLCASK"))
    }
}
