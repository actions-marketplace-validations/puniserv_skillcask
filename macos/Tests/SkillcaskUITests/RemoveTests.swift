import Foundation
import SkillcaskCore
import SkillcaskDomain
import Testing

@testable import SkillcaskUI

/// The Remove alert (S10). A system alert cannot be rendered, so its words are pinned here: the skill → package
/// mapping `remove` needs, what goes along, what stays (refusals, packages kept as dependencies), the agents and the
/// two files, what the button runs, and the not managed explanation with its validated Reveal in Finder.
@Suite @MainActor struct RemoveTests {
    let client = FakeCLIClient()
    let api = Boot.apiScope

    func store(_ scope: Scope, _ snapshot: ScopeSnapshot) -> ScopeStore {
        let store = ScopeStore(
            scope: scope, client: client, capabilities: Capabilities(version: Capabilities.minimum)
        ) { _ in SkillText.parse("# fake") }
        store.preload(snapshot: snapshot)
        return store
    }

    /// `info <package>` answered with `why`, loaded into the store's session cache as the Versions tab would.
    func loadWhy(_ package: String, _ why: [String], into store: ScopeStore) async {
        let lines = String(decoding: (try? JSONEncoder().encode(why)) ?? Data("[]".utf8), as: UTF8.self)
        let json = #"""
            {"package":"\#(package)","source":"composer","repository":null,"version":"1.0.0","locked":true,
            "description":null,"license":[],"abandoned":null,"versions":["1.0.0"],"requires":{},"skills":[],
            "why":\#(lines)}
            """#
        await client.json(.info(.package(package)), in: store.scope, json)
        await store.loadPackageInfo(package)
    }

    // MARK: - Plan

    @Test func skillsMapToPackagesWithoutDuplicates() {
        let plan = RemovePlan(skills: ["pdf", "test-writer", "review-pr"], snapshot: DesignFixtures.api)
        #expect(plan.packages == ["anthropics/skills", "acme/review-pr"])
        #expect(plan.selected == ["pdf", "test-writer", "review-pr"] && plan.siblings.isEmpty)
        #expect(plan.command == .remove(packages: ["anthropics/skills", "acme/review-pr"]))
    }

    /// `remove` takes a package: every skill of it goes, selected or not.
    @Test func theOtherSkillsOfThePackageGoToo() {
        let plan = RemovePlan(skills: ["pdf"], snapshot: DesignFixtures.api)
        #expect(plan.packages == ["anthropics/skills"] && plan.siblings == ["test-writer"])
        #expect(plan.removedSkills == ["pdf", "test-writer"])
        #expect(plan.unchecked == ["pdf", "test-writer"], "no `why` loaded: whether something requires it is unknown")
    }

    /// Remove board "Dependency chain": removing caveman takes safe-refactor, which only caveman requires.
    @Test func anOrphanedDependencyGoesWithItsRequirer() {
        let plan = RemovePlan(skills: ["caveman"], snapshot: DesignFixtures.apiTagMoved)
        #expect(plan.packages == ["juliusbrussee/caveman"])
        #expect(plan.orphans == [.init(skill: "safe-refactor", requirers: ["caveman"])])
        #expect(plan.removedSkills.count == 2 && RemoveCopy.button(count: 2) == "Remove 2 Skills")
    }

    /// `src/commands.rs` `remove` keeps a package another one requires ("kept … as a dependency"): its files stay.
    @Test func aPackageAnotherRequiresIsKept() {
        let why = [
            "acme/commit": ["acme/commit: in skills.toml as \"^3.0\"", "acme/commit: required by acme/lint (2.3.1)"]
        ]
        let plan = RemovePlan(skills: ["commit-message"], snapshot: DesignFixtures.api, why: why)
        #expect(plan.command == .remove(packages: ["acme/commit"]))
        #expect(plan.kept == [.init(package: "acme/commit", skills: ["commit-message"], requirers: ["legacy-lint"])])
        #expect(plan.removedSkills.isEmpty && plan.unchecked.isEmpty)
        let removedTogether = RemovePlan(
            skills: ["commit-message", "legacy-lint"], snapshot: DesignFixtures.api,
            why: why.merging(["acme/lint": []]) { $1 })
        #expect(removedTogether.kept.isEmpty, "a requirer removed in the same command does not keep it")
    }

    /// `src/commands.rs` `why`: `{n}: required by {r1} ({c1}), {r2} ({c2})`, walked transitively.
    @Test func whyLinesAreReadAsTheCLIWritesThem() {
        let why = [
            "acme/commit: in skills.toml as \"^3.0\"",
            "acme/commit: required by acme/lint (^3.0), acme/review-pr (>=3.0, <4)",
            "acme/lint: required by acme/other (^2)",
            "acme/review-pr: in skills.toml as \"^2.0\"",
        ]
        #expect(RemovePlan.requirers(of: "acme/commit", why: why) == ["acme/lint", "acme/review-pr"])
        #expect(RemovePlan.requirers(of: "acme/lint", why: why) == ["acme/other"])
        #expect(RemovePlan.requirers(of: "acme/review-pr", why: why).isEmpty)
        #expect(
            RemovePlan.requirers(
                of: "acme/commit", why: ["acme/commit: in skills.lock only; nothing in skills.toml requires it"]
            )
            .isEmpty)
    }

    /// Kept when ANY requirer stays; a transitive line about another package never keeps it; deleted when every
    /// requirer goes in the same command.
    @Test func keptOnlyWhileARequirerStays() {
        let why = ["acme/commit: required by acme/lint (^3.0), acme/review-pr (^3.0)"]
        let oneRemoved = RemovePlan(
            skills: ["commit-message", "legacy-lint"], snapshot: DesignFixtures.api,
            why: ["acme/commit": why, "acme/lint": []])
        #expect(oneRemoved.kept.map(\.package) == ["acme/commit"])
        #expect(oneRemoved.kept.first?.requirers == ["review-pr"])
        let transitiveOnly = RemovePlan(
            skills: ["commit-message"], snapshot: DesignFixtures.api,
            why: [
                "acme/commit": ["acme/commit: in skills.toml as \"^3\"", "acme/lint: required by acme/api-docs (^2)"]
            ])
        #expect(transitiveOnly.kept.isEmpty && transitiveOnly.removedSkills == ["commit-message"])
        let allRemoved = RemovePlan(
            skills: ["commit-message", "legacy-lint", "review-pr"], snapshot: DesignFixtures.api,
            why: ["acme/commit": why, "acme/lint": [], "acme/review-pr": []])
        #expect(allRemoved.kept.isEmpty && allRemoved.removedSkills.contains("commit-message"))
    }

    /// A small scope for the reachability cases: a, k and p in skills.toml, d a dependency of a.
    func graphSnapshot() throws -> ScopeSnapshot {
        func row(_ skill: String, _ package: String, via: String = "null") -> String {
            #"{"package":"\#(package)","skill":"\#(skill)","version":"1.0.0","state":"ok","ok":true,"via":\#(via)}"#
        }
        let status =
            #"{"ok":true,"entries":["#
            + [row("a", "x/a"), row("k", "x/k"), row("p", "x/p"), row("d", "x/d", via: #"["x/a"]"#)]
            .joined(separator: ",")
            + "]}"
        let document = try JSONDecoder().decode(StatusDocument.self, from: Data(status.utf8))
        return ScopeSnapshot(status: document, audit: nil, doctor: nil, outdated: nil)
    }

    /// `deps::wanted` reachability: p is required only by d, d only by a. Removing p and a leaves nothing that
    /// reaches d or p, so both go (as `settle_deps` does) and nothing is said to be kept.
    @Test func keptAndGoingAreOneFixpoint() throws {
        let snapshot = try graphSnapshot()
        let why = ["x/p": ["x/p: in skills.toml as \"^1\"", "x/p: required by x/d (^1)", "x/d: required by x/a (^1)"]]
        let both = RemovePlan(skills: ["p", "a"], snapshot: snapshot, why: why)
        #expect(both.kept.isEmpty)
        #expect(both.selected == ["p", "a"] && both.orphans.map(\.skill) == ["d"])
        // a stays: the chain a → d → p keeps p installed, and d is no orphan.
        let chain = RemovePlan(skills: ["p"], snapshot: snapshot, why: why)
        #expect(chain.kept == [.init(package: "x/p", skills: ["p"], requirers: ["d"])])
        #expect(chain.removedSkills.isEmpty && chain.orphans.isEmpty)
    }

    /// `deps::wanted` roots at every manifest entry: a drifted one (`status` prints it as a package-only row) still
    /// keeps what it requires; a lock-only `not in skills.toml` row does not.
    @Test func aDriftedManifestEntryIsARoot() throws {
        func snapshot(_ state: String) throws -> ScopeSnapshot {
            let status =
                #"{"ok":false,"entries":[{"package":"x/p","skill":"p","version":"1.0.0","state":"ok","ok":true},"#
                + #"{"package":"x/r","skill":null,"version":"1.0.0","state":"\#(state)","ok":false}]}"#
            let document = try JSONDecoder().decode(StatusDocument.self, from: Data(status.utf8))
            return ScopeSnapshot(status: document, audit: nil, doctor: nil, outdated: nil)
        }
        let why = ["x/p": ["x/p: in skills.toml as \"^1\"", "x/p: required by x/r (^1)"]]
        let drifted = RemovePlan(
            skills: ["p"], snapshot: try snapshot(#"constraint changed from \"^1\" to \"^2\""#), why: why)
        #expect(drifted.kept == [.init(package: "x/p", skills: ["p"], requirers: ["x/r"])])
        let lockOnly = RemovePlan(skills: ["p"], snapshot: try snapshot("not in skills.toml"), why: why)
        #expect(lockOnly.kept.isEmpty && lockOnly.removedSkills == ["p"])
        // A drifted dependency D (`x/d` via x/a, no skill) requiring p keeps nothing once its requirer a goes.
        let status =
            #"{"ok":false,"entries":[{"package":"x/p","skill":"p","version":"1.0.0","state":"ok","ok":true},"#
            + #"{"package":"x/a","skill":"a","version":"1.0.0","state":"ok","ok":true},"#
            + #"{"package":"x/d","via":["x/a"],"skill":null,"version":"1.0.0","#
            + #""state":"constraint changed from \"^1\" to \"^2\"","ok":false}]}"#
        let dependency = ScopeSnapshot(
            status: try JSONDecoder().decode(StatusDocument.self, from: Data(status.utf8)), audit: nil, doctor: nil,
            outdated: nil)
        #expect(dependency.entries.first { $0.id == "x/d" }?.via == ["x/a"])
        let chainWhy = [
            "x/p": ["x/p: in skills.toml as \"^1\"", "x/p: required by x/d (^1)", "x/d: required by x/a (^1)"]
        ]
        let bothGo = RemovePlan(skills: ["p", "a"], snapshot: dependency, why: chainWhy)
        #expect(bothGo.kept.isEmpty && bothGo.removedSkills.contains("p"))
        let aStays = RemovePlan(skills: ["p"], snapshot: dependency, why: chainWhy)
        #expect(aStays.kept.map(\.package) == ["x/p"], "while a stays, the drifted d still keeps p")
    }

    @Test func aRequiresCycleTerminates() throws {
        let snapshot = try graphSnapshot()
        let why = ["x/p": ["x/p: required by x/q (^1)", "x/q: required by x/p (^1)"]]
        let plan = RemovePlan(skills: ["p"], snapshot: snapshot, why: why)
        #expect(plan.kept.isEmpty && plan.removedSkills == ["p"], "an unreachable cycle keeps nothing alive")
        let edges = RemovePlan.edges(entries: snapshot.entries, why: why)
        #expect(RemovePlan.reachable(from: ["x/q"], edges: edges) == ["x/q", "x/p"])
    }

    @Test func dependencyProjectAndHandWrittenSkillsAreRefused() {
        let plan = RemovePlan(skills: ["safe-refactor", "my-notes", "deploy-checklist"], snapshot: DesignFixtures.api)
        #expect(plan.isEmpty && plan.command == nil)
        #expect(
            plan.refusals == [
                .dependency(skill: "safe-refactor", requirers: ["caveman"]), .project("my-notes"),
                .handWritten("deploy-checklist"),
            ])
        #expect(
            RemoveCopy.refusal(plan.refusals[0])
                == "safe-refactor is a dependency of caveman and stays; remove what requires it instead.")
    }

    @Test func notManagedSkillsAreNeverRemoved() {
        let alone = RemovePlan(skills: ["standup-summary"], snapshot: DesignFixtures.personal)
        #expect(alone.notManaged.map(\.id) == ["standup-summary"] && alone.command == nil)
        let mixed = RemovePlan(skills: ["standup-summary", "review-pr"], snapshot: DesignFixtures.personal)
        #expect(mixed.notManaged.isEmpty && mixed.packages == ["acme/review-pr"])
        #expect(mixed.refusals == [.notManaged("standup-summary")])
    }

    // MARK: - Words

    /// Remove board "Single", with the hedge while nobody has loaded who requires the package.
    @Test func singleNamesTheAgentsAndTheTwoFiles() async {
        let store = store(api, DesignFixtures.api)
        let unchecked = RemoveAlert(skills: ["review-pr"], store: store)
        #expect(unchecked.title == "Remove review-pr from this project?")
        #expect(
            unchecked.messageText
                == "review-pr will no longer be available to Claude Code and Cursor in this project. If another "
                + "package requires review-pr, it stays installed as a dependency. skills.toml and skills.lock will "
                + "be updated and the files deleted.")
        await loadWhy("acme/review-pr", ["acme/review-pr: in skills.toml as \"^2.0\""], into: store)
        let checked = RemoveAlert(skills: ["review-pr"], store: store)
        #expect(
            checked.messageText
                == "review-pr will no longer be available to Claude Code and Cursor in this project. skills.toml and "
                + "skills.lock will be updated and the files deleted.")
        #expect(checked.offer == .remove(count: 1))
    }

    /// Remove board "Multi-select": names listed, agents once.
    @Test func multiSelectListsTheNamesAndSumsTheAgents() async {
        let store = store(api, DesignFixtures.api)
        for package in ["acme/lint", "acme/sql-review", "acme/review-pr"] {
            await loadWhy(package, [], into: store)
        }
        let alert = RemoveAlert(skills: ["legacy-lint", "sql-review", "review-pr"], store: store)
        #expect(alert.title == "Remove 3 skills from this project?")
        #expect(
            alert.messageText
                == "legacy-lint, sql-review and review-pr will no longer be available to Claude Code and Cursor in "
                + "this project. skills.toml and skills.lock will be updated and the files deleted.")
        #expect(alert.offer == .remove(count: 3) && RemoveCopy.button(count: 3) == "Remove 3 Skills")
    }

    /// Remove board "Dependency chain", in My Skills (no "in this project").
    @Test func theDependencySentenceAndThePersonalScope() async {
        let store = store(.personal, DesignFixtures.apiTagMoved)
        await loadWhy("juliusbrussee/caveman", [], into: store)
        let alert = RemoveAlert(skills: ["caveman"], store: store)
        #expect(alert.title == "Remove caveman from My Skills?")
        #expect(
            alert.messageText
                == "caveman will no longer be available to Claude Code and Cursor. safe-refactor is only here because "
                + "caveman requires it and will be removed too. skills.toml and skills.lock will be updated and the "
                + "files deleted.")
        #expect(alert.offer == .remove(count: 2))
    }

    @Test func aKeptPackageIsNotSaidToBeDeleted() async {
        let store = store(api, DesignFixtures.api)
        await loadWhy("acme/commit", ["acme/commit: required by acme/lint (2.3.1)"], into: store)
        let alert = RemoveAlert(skills: ["commit-message"], store: store)
        #expect(alert.title == "Remove commit-message from this project?")
        #expect(
            alert.messageText
                == "commit-message stays installed because legacy-lint requires it; only its entry in skills.toml is "
                + "removed. skills.toml and skills.lock will be updated.")
        #expect(alert.offer == .remove(count: 0) && RemoveCopy.button(count: 0) == "Remove")
    }

    @Test func theSiblingsAndTheRefusalsAreSaid() {
        let alert = RemoveAlert(skills: ["pdf", "my-notes"], store: store(api, DesignFixtures.api))
        #expect(alert.title == "Remove pdf from this project?")
        #expect(
            alert.messageText
                == "pdf will no longer be available to Claude Code and Cursor in this project. test-writer is part of "
                + "the same package and will be removed too. If another package requires any of them, that one "
                + "stays installed as a dependency. my-notes is a project skill and stays; edit it in the "
                + "repository. skills.toml and skills.lock will be updated and the files deleted.")
        #expect(alert.offer == .remove(count: 2))
    }

    @Test func siblingsSayPackageOrPackages() {
        #expect(
            RemoveCopy.siblings(["a", "b"], packages: 1)
                == "a and b are part of the same package and will be removed too.")
        #expect(
            RemoveCopy.siblings(["a", "b"], packages: 2)
                == "a and b are part of the same packages and will be removed too.")
        #expect(RemoveCopy.siblings(["a"], packages: 1) == "a is part of the same package and will be removed too.")
    }

    @Test func nothingRemovableOffersOnlyOK() {
        let alert = RemoveAlert(skills: ["safe-refactor"], store: store(api, DesignFixtures.api))
        #expect(alert.title == "Can’t remove safe-refactor" && alert.offer == .nothing)
        #expect(!alert.messageText.contains("skills.lock will be updated"))
    }

    /// No app-side file change (spec D35): a not managed skill is explained and revealed, never trashed.
    @Test func notManagedIsExplainedAndRevealed() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "remove-personal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(path: ".claude/skills/standup-summary"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let alert = RemoveAlert(
            skills: ["standup-summary"], store: store(.personal, DesignFixtures.personal), root: root)
        #expect(alert.title == "standup-summary is not managed by Skillcask")
        #expect(
            alert.messageText
                == "Skillcask does not manage this skill, so it has nothing to remove. Nothing in skills.toml or "
                + "skills.lock changes. To delete it, reveal it in Finder and move it to the Trash yourself.")
        let folder = root.standardizedFileURL.appending(path: ".claude/skills/standup-summary").standardizedFileURL
        #expect(alert.offer == .reveal(folder))
        var revealed: [URL] = []
        let runner = ActionRunner(queue: MutationQueue())
        #expect(alert.confirm(runner: runner, reveal: { revealed.append($0) }) == nil)
        #expect(revealed == [folder] && runner.outcome == nil)
    }

    @Test func theRevealedFolderStaysInsideTheScopeRoot() {
        let root = URL(fileURLWithPath: "/tmp/scope-root")
        func entry(_ name: String, path: String? = nil) -> SkillEntry {
            SkillEntry(
                id: name, name: name, kind: .notManaged(adopt: nil), source: nil, version: nil, state: .notManaged,
                health: .notManaged, update: nil, findings: [], path: path, description: nil)
        }
        let targets = try? JSONDecoder()
            .decode(
                StatusDocument.Targets.self, from: Data(#"{"entries":["claude"],"dirs":[".claude/skills"]}"#.utf8))
        #expect(
            RemoveAlert.folder(of: entry("notes"), targets: targets, root: root)?.path
                == "/tmp/scope-root/.claude/skills/notes")
        #expect(
            RemoveAlert.folder(of: entry("notes", path: ".agents/skills/notes"), targets: targets, root: root)?.path
                == "/tmp/scope-root/.agents/skills/notes")
        for bad in ["..", ".", "a/b", ""] {
            #expect(RemoveAlert.folder(of: entry(bad), targets: targets, root: root) == nil, "name \(bad)")
        }
        for bad in ["../outside", "/etc", "~/x", ".claude/../../x", "./x"] {
            #expect(RemoveAlert.folder(of: entry("n", path: bad), targets: targets, root: root) == nil, "path \(bad)")
        }
        #expect(RemoveAlert.folder(of: entry("notes"), targets: nil, root: root) == nil)
    }

    /// Reveal resolves symbolic links before it opens anything: a linked component pointing outside the scope root
    /// is refused even though the path is lexically inside.
    @Test func revealRefusesALinkOutOfTheRoot() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "remove-tests-\(UUID().uuidString)")
        let root = base.appending(path: "root")
        let outside = base.appending(path: "outside")
        try FileManager.default.createDirectory(
            at: root.appending(path: ".claude/skills/plain"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: outside.appending(path: "skills/linked"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appending(path: ".codex"), withDestinationURL: outside)
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(RemoveAlert.staysInside(root.appending(path: ".claude/skills/plain"), root: root))
        #expect(!RemoveAlert.staysInside(root.appending(path: ".codex/skills/linked"), root: root))
        #expect(RemoveAlert.isSafe(".codex/skills/linked"), "lexically fine: only the resolved check catches it")
    }

    /// The offer is decided at request time with links resolved: a Reveal that would do nothing is never offered.
    @Test func revealIsOfferedOnlyWhenTheResolvedFolderIsInside() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "remove-offer-\(UUID().uuidString)")
        let plain = base.appending(path: "plain")
        let linked = base.appending(path: "linked")
        let outside = base.appending(path: "outside")
        try FileManager.default.createDirectory(
            at: plain.appending(path: ".claude/skills/standup-summary"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: outside.appending(path: "skills/standup-summary"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linked.appending(path: ".claude"), withDestinationURL: outside)
        defer { try? FileManager.default.removeItem(at: base) }
        let inside = RemoveAlert(skills: ["standup-summary"], store: store(.project(plain), DesignFixtures.personal))
        guard case .reveal = inside.offer else {
            Issue.record("a plain folder inside the root is offered for Reveal")
            return
        }
        let escaping = RemoveAlert(skills: ["standup-summary"], store: store(.project(linked), DesignFixtures.personal))
        #expect(escaping.offer == .nothing && escaping.revealURL == nil)
    }

    // MARK: - Running

    @Test func removeTakesPackagesAfterTheSeparator() throws {
        let invocation = try Invocation(
            .remove(packages: ["anthropics/skills", "acme/review-pr"]), in: api,
            capabilities: Capabilities(version: Capabilities.minimum))
        #expect(invocation.argv == ["remove", "--", "anthropics/skills", "acme/review-pr"])
    }

    func scriptRefresh(_ scope: Scope) async {
        await client.json(.status, in: scope, ScopeStoreTests.status([("x", "1.0.0")]))
        await client.json(.audit, in: scope, ScopeStoreTests.emptyAudit)
        await client.json(.doctor(fix: false), in: scope, ScopeStoreTests.cleanDoctor)
    }

    @Test(.timeLimit(.minutes(1))) func confirmRunsRemoveFromTheWindowWithAToast() async {
        await client.lines(.remove(packages: ["anthropics/skills"]), in: api, ["removed anthropics/skills"])
        await scriptRefresh(api)
        let runner = ActionRunner(queue: MutationQueue())
        let alert = RemoveAlert(skills: ["pdf"], store: store(api, DesignFixtures.api))
        await alert.confirm(runner: runner)?.value
        #expect(await client.commands.first == .remove(packages: ["anthropics/skills"]))
        #expect(runner.toast?.text == "Removed 2 skills from api")
        #expect(runner.activity.first?.title == "Removing 2 skills…")
    }

    /// The CLI's `kept … as a dependency` line wins over the plan: no "Removed" for a package it kept.
    @Test(.timeLimit(.minutes(1))) func theToastFollowsWhatTheCLIKept() async {
        await client.lines(
            .remove(packages: ["acme/commit"]), in: api,
            ["kept acme/commit as a dependency", "  required by: acme/lint (^3)"])
        await scriptRefresh(api)
        let runner = ActionRunner(queue: MutationQueue())
        let alert = RemoveAlert(skills: ["commit-message"], store: store(api, DesignFixtures.api))
        await alert.confirm(runner: runner)?.value
        #expect(runner.toast?.text == "Kept acme/commit as a dependency in api")
    }

    /// Retry ends exactly as the first run would have: the same transcript-built toast, never an empty one.
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func retryAfterAFailedRemoveToastsLikeTheFirstRun(kept: Bool) async throws {
        let network = CLIError.failed(code: .network, message: "no route to host", hint: nil, stderr: "")
        await client.script(.remove(packages: ["acme/commit"]), in: api, .error(network))
        await scriptRefresh(api)
        let lines = kept ? ["kept acme/commit as a dependency"] : ["removed acme/commit"]
        await client.lines(.remove(packages: ["acme/commit"]), in: api, lines)
        await scriptRefresh(api)
        let runner = ActionRunner(queue: MutationQueue())
        let alert = RemoveAlert(skills: ["commit-message"], store: store(api, DesignFixtures.api))
        await alert.confirm(runner: runner)?.value
        #expect(runner.banner?.title == "Couldn’t remove commit-message.")
        await runner.retry()?.value
        let expected = kept ? "Kept acme/commit as a dependency in api" : "Removed commit-message from api"
        #expect(runner.toast?.text == expected)
        #expect(runner.activity.map(\.title) == ["Removing commit-message…", "Removing commit-message…"])
    }

    @Test(.timeLimit(.minutes(1))) func aFailedRemoveIsTitledWithTheVerb() async {
        await client.script(
            .remove(packages: ["acme/review-pr"]), in: api,
            .error(.failed(code: .other(1), message: "skills.toml is locked", hint: nil, stderr: "")))
        await scriptRefresh(api)
        let runner = ActionRunner(queue: MutationQueue())
        await RemoveAlert(skills: ["review-pr"], store: store(api, DesignFixtures.api)).confirm(runner: runner)?.value
        #expect(runner.banner?.title == "Couldn’t remove review-pr.")
    }

    @Test func confirmWhileAnotherRunIsInFlightRunsNothing() async {
        let runner = ActionRunner(queue: MutationQueue())
        runner.preloadRunning(title: "Syncing…", in: api)
        let alert = RemoveAlert(skills: ["review-pr"], store: store(api, DesignFixtures.api))
        #expect(alert.confirm(runner: runner) == nil)
        #expect(
            runner.banner?.title == "Couldn’t remove review-pr."
                && runner.banner?.reason == SheetCopy.anotherRunInFlight)
        #expect(await client.commands.isEmpty)
    }
}
