import Foundation
import SkillcaskCore
import SkillcaskDomain
import Testing

@testable import SkillcaskUI

/// The Adopt sheet (S9): what `AdoptPlan` offers over the personal fixture, the project-scope gate, the command
/// line, the batch through `SheetRun.startBatch` with the sheet's own commands, and the board's words.
@Suite @MainActor struct AdoptTests {
    let client = FakeCLIClient()
    let personal = Scope.personal
    let project = Scope.project(URL(fileURLWithPath: "/tmp/adopt-tests"))

    func store(_ scope: Scope) -> ScopeStore {
        ScopeStore(scope: scope, client: client, capabilities: Capabilities(version: Capabilities.minimum)) { _ in
            SkillText.parse("# fake")
        }
    }

    var notManaged: [String] {
        DesignFixtures.personal.entries.filter(\.isNotManaged).map(\.id)
    }

    // MARK: - Plan

    @Test func theBatchSplitsKnownFromUnknownSources() {
        let plan = AdoptPlan(skills: notManaged, entries: DesignFixtures.personal.entries, scope: personal)
        #expect(plan.isAvailable && plan.isBatch)
        #expect(plan.items.count == 12 && plan.known.count == 9 && plan.unknown.count == 3)
        #expect(plan.unknown.map(\.name) == ["standup-summary", "meeting-prep", "retro-notes"])
        #expect(
            plan.known.first
                == .init(id: "caveman", name: "caveman", spec: "github:juliusbrussee/caveman", version: "4.0.1"))
    }

    @Test func managedOrMissingSkillsAreLeftOut() {
        let plan = AdoptPlan(
            skills: ["caveman", "review-pr", "gone"], entries: DesignFixtures.personal.entries, scope: personal)
        #expect(plan.items.map(\.id) == ["caveman"] && !plan.isBatch)
    }

    @Test func adoptAllListsEveryNotManagedRowOnlyWhenOneHasASource() {
        #expect(AdoptPlan.batchSkills(DesignFixtures.personal.entries) == notManaged)
        #expect(AdoptPlan.batchSkills(DesignFixtures.website.entries) == nil)
        let unknownOnly = DesignFixtures.personal.entries.filter { $0.id == "standup-summary" }
        #expect(AdoptPlan.batchSkills(unknownOnly) == nil)
    }

    // MARK: - Project gate and command line

    /// `src/commands.rs` `adopt`: "--adopt applies only with --global". A project never gets a command.
    @Test func aProjectCannotAdopt() {
        let plan = AdoptPlan(skills: ["caveman"], entries: DesignFixtures.api.entries, scope: project)
        #expect(!plan.isAvailable && plan.items.map(\.id) == ["caveman"])
        #expect(AdoptPlan.command(spec: "github:juliusbrussee/caveman", scope: project) == nil)
        #expect(AdoptCopy.projectBody(skills: ["caveman"]).hasPrefix("Adopting works only in My Skills."))
    }

    @Test func adoptIsGlobalAddWithAdoptAfterTheSeparator() throws {
        let command = try #require(AdoptPlan.command(spec: " github:juliusbrussee/caveman ", scope: personal))
        let invocation = try Invocation(
            command, in: personal, capabilities: Capabilities(version: Capabilities.minimum))
        #expect(invocation.argv == ["-g", "add", "--adopt", "--", "github:juliusbrussee/caveman"])
        #expect(AdoptPlan.command(spec: "  ", scope: personal) == nil)
    }

    // MARK: - Batch

    func command(_ skill: String) -> Invocation.Command {
        let spec = DesignFixtures.personal.entries.first { $0.id == skill }
            .flatMap {
                if case .notManaged(let adopt) = $0.kind { adopt } else { nil }
            }
        return AdoptPlan.command(spec: spec ?? "", scope: personal)
            ?? .add(spec: "", repository: nil, adopt: true, rename: [:], skills: [])
    }

    func scriptRefresh() async {
        await client.json(.status, in: personal, ScopeStoreTests.status([("x", "1.0.0")]))
        await client.json(.audit, in: personal, ScopeStoreTests.emptyAudit)
        await client.json(.doctor(fix: false), in: personal, ScopeStoreTests.cleanDoctor)
    }

    func batch(
        _ skills: [String], _ run: SheetRun, store: ScopeStore, runner: ActionRunner,
        onSuccess: @escaping @MainActor () -> Void
    ) -> Task<Void, Never>? {
        run.startBatch(
            skills, title: AdoptCopy.runningBatch(count: skills.count), command: command,
            itemTitle: AdoptCopy.running, itemFailure: AdoptCopy.couldNotAdopt,
            summary: { AdoptCopy.summary(done: $0, scope: $1) }, in: store,
            runner: runner, onSuccess: onSuccess)
    }

    @Test(.timeLimit(.minutes(1))) func theBatchRunsInOrderAndEndsWithOneToast() async {
        let skills = ["caveman", "pdf", "commit-message"]
        for skill in skills {
            await client.lines(command(skill), in: personal, ["adopted .claude/skills/\(skill)"])
            await scriptRefresh()
        }
        let runner = ActionRunner(queue: MutationQueue())
        let run = SheetRun()
        var closed = false
        await batch(skills, run, store: store(personal), runner: runner) { closed = true }?.value
        let adds = await client.invocations.filter { if case .add = $0.command { true } else { false } }
        #expect(
            adds.map(\.argv.last) == ["github:juliusbrussee/caveman", "github:anthropics/skills/pdf", "acme/commit"])
        #expect(adds.allSatisfy { $0.argv.prefix(3) == ["-g", "add", "--adopt"] })
        #expect(run.phase == .succeeded && closed && run.doneCount == 3)
        #expect(runner.toast?.text == "Adopted 3 skills in My Skills")
        #expect(runner.activity.map(\.title) == ["Adopting commit-message…", "Adopting pdf…", "Adopting caveman…"])
    }

    @Test(.timeLimit(.minutes(1))) func aFailureStopsTheRest() async {
        await client.lines(command("caveman"), in: personal, [])
        await scriptRefresh()
        await client.script(
            command("pdf"), in: personal,
            .error(.failed(code: .network, message: "no route to host", hint: nil, stderr: "")))
        await scriptRefresh()
        let runner = ActionRunner(queue: MutationQueue())
        let run = SheetRun()
        var closed = false
        await batch(["caveman", "pdf", "commit-message"], run, store: store(personal), runner: runner) {
            closed = true
        }?
        .value
        #expect(!closed && run.failure?.title == "Couldn’t adopt pdf." && run.canClose)
        #expect(run.items.last?.state == .skipped && run.items.filter { $0.state == .skipped }.count == 1)
        #expect(runner.toast?.text == "Adopted 1 skill in My Skills" && runner.banner == nil)
        #expect(!(await client.commands.contains(command("commit-message"))))
        #expect(
            AdoptCopy.ended(done: run.doneCount, of: 3, failed: true)
                == "Adopted 1 of 3 skills; a failure stopped the rest.")
    }

    @Test(.timeLimit(.minutes(1))) func cancelStopsAfterTheCurrentItem() async {
        let gate = Gate()
        await client.lines(command("caveman"), in: personal, [], gate: gate)
        await scriptRefresh()
        let runner = ActionRunner(queue: MutationQueue())
        let run = SheetRun()
        let task = batch(["caveman", "pdf"], run, store: store(personal), runner: runner) {}
        await gate.arrived()
        #expect(!run.canClose && run.items.first?.state == .running)
        run.cancel()
        await gate.open()
        await task?.value
        #expect(run.phase == .stopped && run.doneCount == 1 && run.items.last?.state == .skipped)
        #expect(!(await client.commands.contains(command("pdf"))))
        #expect(runner.toast?.text == "Adopted 1 skill in My Skills")
    }

    // MARK: - Failure titles

    /// A failure names the verb ("Couldn’t adopt caveman."), never the progress title ("Couldn’t Adopting caveman….").
    @Test(.timeLimit(.minutes(1))) func aFailedAdoptIsTitledWithTheVerb() async {
        await client.script(
            command("caveman"), in: personal, .error(.failed(code: .other(1), message: "no", hint: nil, stderr: "")))
        await scriptRefresh()
        let run = SheetRun()
        await run.start(
            command("caveman"), title: AdoptCopy.running("caveman"), failure: AdoptCopy.couldNotAdopt("caveman"),
            outcome: { _ in "" }, in: store(personal), runner: ActionRunner(queue: MutationQueue()), onSuccess: {}
        )?
        .value
        #expect(run.failure?.title == "Couldn’t adopt caveman.")
    }

    @Test func aRefusedAdoptKeepsTheVerbTitle() {
        let runner = ActionRunner(queue: MutationQueue())
        runner.preloadRunning(title: "Syncing…", in: personal)
        let run = SheetRun()
        #expect(
            run.start(
                command("caveman"), title: AdoptCopy.running("caveman"), failure: AdoptCopy.couldNotAdopt("caveman"),
                outcome: { _ in "" }, in: store(personal), runner: runner, onSuccess: {}) == nil)
        #expect(run.failure?.title == "Couldn’t adopt caveman.")
    }

    /// A batch that cannot start (another command runs) is titled with the verb, not "Couldn’t Adopting 2 skills…."
    @Test func aRefusedBatchKeepsTheVerbTitle() {
        let runner = ActionRunner(queue: MutationQueue())
        runner.preloadRunning(title: "Syncing…", in: personal)
        let run = SheetRun()
        let task = run.startBatch(
            ["caveman", "pdf"], title: AdoptCopy.runningBatch(count: 2),
            failure: AdoptCopy.couldNotAdoptBatch(count: 2),
            command: command, itemTitle: AdoptCopy.running, itemFailure: AdoptCopy.couldNotAdopt,
            summary: { AdoptCopy.summary(done: $0, scope: $1) }, in: store(personal), runner: runner, onSuccess: {})
        #expect(task == nil && run.items.isEmpty)
        #expect(run.failure?.title == "Couldn’t adopt 2 skills." && run.failure?.reason == SheetCopy.anotherRunInFlight)
    }

    /// The window's runs name their verb too (`ActionRunner.sync` etc.).
    @Test func windowActionsHaveVerbFailureTitles() {
        #expect(ActionCopy.couldNotSync == "Couldn’t sync.")
        #expect(ActionCopy.couldNotCheck == "Couldn’t check.")
        #expect(ActionCopy.couldNotRepair == "Couldn’t repair.")
        #expect(ActionCopy.couldNotSetUp == "Couldn’t set up.")
        #expect(ActionCopy.couldNotRestore == "Couldn’t restore from the lock.")
        #expect(RemoveCopy.couldNotRemove(["pdf"]) == "Couldn’t remove pdf.")
        #expect(RemoveCopy.couldNotRemove(["a", "b"]) == "Couldn’t remove 2 skills.")
    }

    // MARK: - Checklist

    /// Adopt-States "Batch": the first rows with a source, two "needs a source" rows in view, "… 6 more".
    @Test func theChecklistKeepsUnknownRowsInView() {
        let plan = AdoptPlan(skills: notManaged, entries: DesignFixtures.personal.entries, scope: personal)
        let collapsed = AdoptSheet.listing(known: plan.known, unknown: plan.unknown, showsAll: false)
        #expect(
            collapsed.rows.map(\.id)
                == ["caveman", "pdf", "frontend-design", "commit-message", "standup-summary", "meeting-prep"])
        #expect(collapsed.hidden == 6 && AdoptCopy.more(collapsed.hidden) == "… 6 more")
        let expanded = AdoptSheet.listing(known: plan.known, unknown: plan.unknown, showsAll: true)
        #expect(expanded.rows.count == 12 && expanded.hidden == 0)
        let few = AdoptSheet.listing(known: Array(plan.known.prefix(3)), unknown: [], showsAll: false)
        #expect(few.rows.count == 3 && few.hidden == 0)
    }

    // MARK: - Words

    @Test func theBoardsWords() {
        #expect(AdoptCopy.title(skills: ["caveman"]) == "Adopt caveman")
        #expect(AdoptCopy.title(skills: Array(repeating: "x", count: 12)) == "Adopt 12 skills")
        #expect(
            AdoptCopy.knownBody(skill: "caveman", folder: "~/.config/skillcask/adopted/")
                == "Skillcask will install caveman from this source and keep your current copy in "
                + "~/.config/skillcask/adopted/ so nothing is lost.")
        #expect(
            AdoptCopy.unknownBody(folder: "~/.config/skillcask/adopted/")
                == "Nothing recorded where this skill came from. Enter the source; your current copy is kept in "
                + "~/.config/skillcask/adopted/.")
        #expect(
            AdoptCopy.batchBody(known: 9, unknown: 3, folder: "~/.config/skillcask/adopted/")
                == "9 have a recorded source and are selected. 3 need a source first. Current copies are kept in "
                + "~/.config/skillcask/adopted/.")
        #expect(AdoptCopy.placeholder == "vendor/name · github:owner/repo · git:https://…")
        #expect(AdoptCopy.adopt(count: 9) == "Adopt 9" && AdoptCopy.adopt(count: nil) == "Adopt")
        #expect(AdoptCopy.batchProgress(count: 9, current: 4) == "Adopting 9 skills · 4 of 9")
        #expect(AdoptCopy.duration(.milliseconds(2100)) == "2.1 s")
        #expect(AdoptCopy.duration(.seconds(64)) == "1 min 4 s")
        #expect(AdoptCopy.elapsed(21.7) == "0:21" && AdoptCopy.elapsed(75) == "1:15")
        #expect(AdoptCopy.problem(.empty) == nil && AdoptCopy.problem(.github) != nil)
        #expect(AdoptCopy.adoptedItem == "Adopted", "0.9.1 does not say whether a copy was moved aside")
    }

    /// The one sentence about `adopted/` names the CLI's real config directory, not a hard-coded path.
    @Test func theAdoptedFolderFollowsTheConfigDirectory() {
        let app = AppStore(
            settings: SettingsStore(defaults: UserDefaults(suiteName: "AdoptTests-\(UUID().uuidString)") ?? .standard),
            client: client, capabilities: Capabilities(version: Capabilities.minimum))
        let custom = app.manifest(of: .personal, base: ["SKILLCASK_HOME": "/opt/skillcask-home", "HOME": "/Users/x"])
        #expect(AdoptSheet.adoptedFolder(manifest: custom) == "/opt/skillcask-home/adopted/")
        let xdg = app.manifest(of: .personal, base: ["XDG_CONFIG_HOME": "/srv/config", "HOME": "/Users/x"])
        #expect(AdoptSheet.adoptedFolder(manifest: xdg) == "/srv/config/skillcask/adopted/")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let standard = app.manifest(of: .personal, base: ["HOME": home])
        #expect(AdoptSheet.adoptedFolder(manifest: standard) == "~/.config/skillcask/adopted/")
    }
}
