import Foundation
import SkillcaskCore
import SkillcaskDomain
import Testing

@testable import SkillcaskUI

/// The fixes from the Flow-F1 and F5 walks: Set Up without a restart, a folder dropped on the sidebar, the
/// Find Projects sheet, the sidebar badges from a background `status`, the not-managed banner's Review, and the rows
/// that fill from `status` before `audit` and `doctor` answer.
@Suite @MainActor struct FlowTests {
    let client = FakeCLIClient()
    let capabilities = Capabilities(version: Capabilities.minimum)

    static func settings() -> SettingsStore {
        AppStoreTests.settings()
    }

    /// A fresh folder under the temporary directory, removed by the caller.
    static func folder(_ name: String = UUID().uuidString) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "FlowTests-\(name)").standardizedFileURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `status` with one entry per `(name, state)`.
    static func status(_ skills: [(name: String, state: String)]) -> String {
        let entries = skills.map {
            #"{"package":"acme/\#($0.name)","skill":"\#($0.name)","version":"1.0.0","state":"\#($0.state)","ok":false}"#
        }
        return #"{"ok":true,"entries":[\#(entries.joined(separator: ","))],"policy":{},"repositories":[]}"#
    }

    static let emptyStatus = #"{"ok":true,"entries":[],"policy":{},"repositories":[]}"#

    func app(_ settings: SettingsStore, manifestExists: @escaping @Sendable (URL) -> Bool = { _ in true }) -> AppStore {
        AppStore(settings: settings, client: client, capabilities: capabilities, manifestExists: manifestExists)
    }

    // MARK: - 1. Set Up

    /// Flow-F1 "Empty after Set Up": `init` writes skills.toml, and the same window then shows the folder set up,
    /// its row without "Not set up", the list's "No skills yet" and the Overview instead of the Set Up block.
    @Test(.timeLimit(.minutes(1))) func setUpTurnsTheFolderIntoAnEmptyProjectWithoutARestart() async throws {
        let root = try Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = Self.settings()
        settings.remember(project: root)
        let app = AppStore(settings: settings, client: client, capabilities: capabilities)
        let scope = Scope.project(root)
        await app.boot()
        #expect(app.item(for: scope)?.isSetUp == false)
        let writing = Gate()
        await client.lines(.initialize, in: scope, ["Created skills.toml"], gate: writing)
        await client.json(.status, in: scope, Self.emptyStatus)
        await client.json(.audit, in: scope, ScopeStoreTests.emptyAudit)
        await client.json(.doctor(fix: false), in: scope, ScopeStoreTests.cleanDoctor)
        let runner = ActionRunner(queue: app.queue)
        let store = try #require(app.store(for: scope))
        app.selectedScope = scope
        let setUp = Task { await app.setUp(store, runner: runner) }
        await writing.arrived()
        // `init` writes the manifest while it runs.
        try Data("[policy]\n".utf8).write(to: root.appending(path: "skills.toml"))
        await writing.open()
        await setUp.value
        #expect(app.item(for: scope)?.isSetUp == true, "the row drops Not set up")
        #expect(ListState.resolve(store: store, running: runner.current).content == .empty, "No skills yet")
        let overview = OverviewState.resolve(
            snapshot: store.snapshot, presentation: store.presentation, isSetUp: true, isPersonal: false,
            hasProjects: true)
        #expect(overview != .notSetUp)
        #expect(await client.commands.contains(.initialize))
    }

    /// A failed `init` leaves the folder not set up: the check asks the disk, not the run.
    @Test(.timeLimit(.minutes(1))) func aFailedSetUpLeavesTheFolderNotSetUp() async throws {
        let root = try Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = Self.settings()
        settings.remember(project: root)
        let app = AppStore(settings: settings, client: client, capabilities: capabilities)
        let scope = Scope.project(root)
        await app.boot()
        await client.lines(.initialize, in: scope, ["error: cannot write"], exit: 1)
        await client.json(.status, in: scope, Self.emptyStatus)
        await client.json(.audit, in: scope, ScopeStoreTests.emptyAudit)
        await client.json(.doctor(fix: false), in: scope, ScopeStoreTests.cleanDoctor)
        let store = try #require(app.store(for: scope))
        await app.setUp(store, runner: ActionRunner(queue: app.queue))
        #expect(app.item(for: scope)?.isSetUp == false)
    }

    // MARK: - 2. Drop a folder

    /// The directories of a drop join the sidebar in their order, the first selected; files and web links are
    /// ignored, and a drop of no directory is refused.
    @Test(.timeLimit(.minutes(1))) func droppedFoldersAreAddedAndTheFirstSelected() async throws {
        let settings = Self.settings()
        let app = app(settings, manifestExists: { $0.lastPathComponent != "bare" })
        let first = URL(fileURLWithPath: "/tmp/flow-drop/api")
        let second = URL(fileURLWithPath: "/tmp/flow-drop/bare")
        let file = URL(fileURLWithPath: "/tmp/flow-drop/notes.txt")
        let web = try #require(URL(string: "https://example.com/folder"))
        let directories: Set<URL> = [first, second, web]
        let check = try #require(
            app.open(dropped: [file, first, web, second], isDirectory: { directories.contains($0) }))
        #expect(settings.recentProjects == [first, second])
        #expect(app.selectedScope == .project(first))
        await check.value
        #expect(app.item(for: .project(second))?.isSetUp == false, "a folder without skills.toml offers Set Up")
        #expect(app.open(dropped: [file], isDirectory: { _ in false }) == nil)
        #expect(settings.recentProjects == [first, second])
    }

    /// Before the CLI is ready nothing is added, whichever way in (drop, Open Folder…, Find Projects).
    @Test func noFolderIsAddedBeforeTheCLIIsReady() {
        let settings = Self.settings()
        let app = AppStore(settings: settings, locator: AppStoreTests.notFound) { _ in FakeCLIClient() }
        #expect(app.open(dropped: [URL(fileURLWithPath: "/tmp")], isDirectory: { _ in true }) == nil)
        #expect(app.open(folders: [URL(fileURLWithPath: "/tmp/flow-unready")]) == nil)
        app.open(folder: URL(fileURLWithPath: "/tmp/flow-unready"))
        #expect(app.selectedScope == nil && settings.recentProjects.isEmpty)
    }

    /// A symlink to a folder is refused, as the CLI refuses a symlinked project directory.
    @Test func aSymlinkedFolderIsNotADirectory() throws {
        let root = try Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appending(path: "real")
        let link = root.appending(path: "link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(AppStore.isDirectory(real))
        #expect(!AppStore.isDirectory(link))
    }

    @Test func theDirectoryCheckReadsTheDisk() throws {
        let root = try Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "SKILL.md")
        try Data("# x\n".utf8).write(to: file)
        #expect(AppStore.isDirectory(root))
        #expect(!AppStore.isDirectory(file))
        #expect(!AppStore.isDirectory(root.appending(path: "missing")))
    }

    // MARK: - 3. Find Projects

    @Test(.timeLimit(.minutes(1))) func findProjectsReadsTheFoldersUnderTheRoot() async throws {
        let root = URL(fileURLWithPath: "/tmp/flow-find")
        let json = #"{"projects":[{"path":"/tmp/flow-find/api"},{"path":"/tmp/flow-find/./site"}]}"#
        await client.json(.projects(roots: [root]), in: .project(root), json)
        let app = app(Self.settings())
        let found = await app.projects(under: root)
        #expect(
            try found.get() == [
                URL(fileURLWithPath: "/tmp/flow-find/api"), URL(fileURLWithPath: "/tmp/flow-find/site"),
            ])
    }

    @Test(.timeLimit(.minutes(1))) func findProjectsReturnsTheFailure() async {
        let root = URL(fileURLWithPath: "/tmp/flow-find-fails")
        let error = CLIError.failed(code: .problem, message: "permission denied", hint: nil, stderr: "")
        await client.script(.projects(roots: [root]), in: .project(root), .error(error))
        let app = app(Self.settings())
        guard case .failure(let failure) = await app.projects(under: root) else {
            Issue.record("expected the failure")
            return
        }
        #expect(failure == error)
    }

    /// Every new folder ticked, the listed ones marked and never added twice, a duplicate hit listed once.
    @Test func thePlanTicksNewFoldersAndMarksListedOnes() {
        let api = URL(fileURLWithPath: "/w/api")
        let site = URL(fileURLWithPath: "/w/site")
        let docs = URL(fileURLWithPath: "/w/docs")
        let plan = FindProjectsPlan(found: [api, site, docs, api], recents: [site])
        #expect(plan.rows.map(\.url) == [api, site, docs])
        #expect(plan.rows.map(\.isAdded) == [false, true, false])
        #expect(plan.rows.map(\.name) == ["api", "site", "docs"])
        #expect(plan.defaultSelection == [api, docs])
        #expect(plan.chosen(plan.defaultSelection) == [api, docs])
        #expect(plan.chosen([docs, site]) == [docs], "a listed folder is never added again")
        #expect(FindProjectsPlan(found: [], recents: [site]).isEmpty)
        #expect(!plan.isAllAdded)
    }

    /// Every hit already listed: the sentence says so and nothing can be added.
    @Test func whenEveryHitIsListedNothingCanBeAdded() {
        let api = URL(fileURLWithPath: "/w/api")
        let site = URL(fileURLWithPath: "/w/site")
        let plan = FindProjectsPlan(found: [api, site], recents: [site, api])
        #expect(plan.isAllAdded && !plan.isEmpty)
        #expect(plan.defaultSelection.isEmpty && plan.chosen([api, site]).isEmpty)
        #expect(FindProjectsCopy.allAdded(2, in: "~/w") == "All 2 projects under ~/w are already in the sidebar.")
        #expect(FindProjectsCopy.allAdded(1, in: "~/w") == "The project under ~/w is already in the sidebar.")
        #expect(!FindProjectsPlan(found: [], recents: []).isAllAdded)
    }

    /// The sheet goes through the guarded request; Add adds the chosen folders and selects the first.
    @Test(.timeLimit(.minutes(1))) func addingTheChosenProjectsSelectsTheFirst() async throws {
        let settings = Self.settings()
        let site = URL(fileURLWithPath: "/w/site")
        settings.remember(project: site)
        let app = app(settings)
        app.selectedScope = .personal
        let root = URL(fileURLWithPath: "/w")
        #expect(app.request(.findProjects(root: root)))
        #expect(app.presentedSheet?.sheet == .findProjects(root: root))
        #expect(!app.request(.findProjects(root: root)), "a second request is refused while it shows")
        let plan = FindProjectsPlan(
            found: [URL(fileURLWithPath: "/w/api"), site, URL(fileURLWithPath: "/w/docs")], recents: [site])
        await app.open(folders: plan.chosen(plan.defaultSelection))?.value
        #expect(settings.recentProjects.map(\.lastPathComponent) == ["api", "docs", "site"])
        #expect(app.selectedScope == .project(URL(fileURLWithPath: "/w/api")))
    }

    // MARK: - 4. Sidebar badges

    /// At launch every set-up project not opened yet gets its badge from one `status`; `outdated` never runs, and a
    /// folder without skills.toml is not asked.
    @Test(.timeLimit(.minutes(1))) func everyRecentProjectGetsAStatusBadgeAtLaunch() async {
        let settings = Self.settings()
        let api = Scope.project(at: "/tmp/flow-badges/api")
        let site = Scope.project(at: "/tmp/flow-badges/site")
        let bare = Scope.project(at: "/tmp/flow-badges/bare")
        for scope in [bare, site, api] {
            settings.remember(project: scope.root)
        }
        await client.json(.status, in: api, Self.status([("pdf", "not installed"), ("docx", "ok")]))
        await client.json(.status, in: site, Self.status([("docx", "ok")]))
        let app = app(settings, manifestExists: { $0.lastPathComponent != "bare" })
        await app.boot()
        await app.summaries.settle()
        #expect(app.attention(for: api)?.needing == 1)
        #expect(app.attention(for: site) == Attention())
        #expect(app.attention(for: bare) == nil)
        let commands = await client.invocations.map { ($0.command, $0.scope) }
        #expect(commands.allSatisfy { $0.0 == .status && $0.1 != bare })
        #expect(commands.count == 2)
    }

    /// No more than `ScopeSummaries.limit` reads run at once; the next starts when one ends.
    @Test(.timeLimit(.minutes(1))) func badgeReadsRunAtMostThreeAtATime() async {
        let scopes = (1...4).map { Scope.project(at: "/tmp/flow-limit/p\($0)") }
        let gates = scopes.map { _ in Gate() }
        for (scope, gate) in zip(scopes, gates) {
            await client.json(.status, in: scope, Self.status([("x", "ok")]), gate: gate)
        }
        let summaries = ScopeSummaries()
        summaries.summarize(scopes, client: client, capabilities: capabilities)
        for gate in gates.prefix(3) {
            await gate.arrived()
        }
        #expect(await client.invocations.count == 3)
        #expect(summaries.isPending(scopes[3]))
        await gates[0].open()
        await gates[3].arrived()
        #expect(await client.invocations.count == 4)
        for gate in gates {
            await gate.open()
        }
        await summaries.settle()
        #expect(scopes.allSatisfy { summaries.attention[$0] == Attention() })
    }

    /// Removing a project cancels its read and drops its badge; a late answer changes nothing.
    @Test(.timeLimit(.minutes(1))) func removingAProjectCancelsItsBadgeRead() async {
        let settings = Self.settings()
        let api = Scope.project(at: "/tmp/flow-remove/api")
        settings.remember(project: api.root)
        let slow = Gate()
        await client.json(.status, in: api, Self.status([("pdf", "not installed")]), gate: slow)
        let app = app(settings)
        await app.boot()
        await slow.arrived()
        #expect(app.summaries.isPending(api))
        app.removeFromSidebar(api)
        #expect(!app.summaries.isPending(api))
        await slow.open()
        await app.summaries.settle()
        #expect(app.attention(for: api) == nil)
    }

    /// My Skills gets a status badge too when another scope opened first.
    @Test(.timeLimit(.minutes(1))) func mySkillsGetsABadgeWhenAnotherScopeIsOpen() async {
        let settings = Self.settings()
        let api = Scope.project(at: "/tmp/flow-personal/api")
        settings.remember(project: api.root)
        await client.json(.status, in: .personal, Self.status([("caveman", "not managed")]))
        let app = app(settings)
        app.selectedScope = api
        await app.boot()
        await app.summaries.settle()
        #expect(app.attention(for: .personal) != nil)
        #expect(await client.invocations.map(\.scope) == [.personal], "the selected project is not summarized")
    }

    /// A failed read is remembered: adding another folder does not ask the failed project again.
    @Test(.timeLimit(.minutes(1))) func aFailedBadgeReadIsNotRepeated() async {
        let settings = Self.settings()
        let api = Scope.project(at: "/tmp/flow-failed/api")
        let site = Scope.project(at: "/tmp/flow-failed/site")
        settings.remember(project: api.root)
        await client.json(.status, in: site, Self.status([("x", "ok")]))
        let app = app(settings)
        await app.boot()
        await app.summaries.settle()
        #expect(app.attention(for: api) == nil)
        app.selectedScope = .personal
        await app.open(folders: [site.root])?.value
        app.selectedScope = .personal
        await app.open(folders: [URL(fileURLWithPath: "/tmp/flow-failed/other")])?.value
        await app.summaries.settle()
        let asked = await client.invocations.filter { $0.scope == api }.count
        #expect(asked == 1)
        app.summaries.reset()
        #expect(!app.summaries.isPending(api))
    }

    /// Once a project has a store, its snapshot is the badge (it knows `audit`, `doctor` and checked updates).
    @Test func aVisitedStoreWinsOverTheSummary() throws {
        let app = app(Self.settings())
        let store = try #require(app.store(for: Boot.apiScope))
        store.preload(snapshot: DesignFixtures.api)
        #expect(app.attention(for: Boot.apiScope) == DesignFixtures.api.attention)
        #expect(app.attention(for: Boot.websiteScope) == nil)
    }

    // MARK: - 5. Review

    /// The banner's Review: the Not managed chip, its first row selected (Flow-F1 step 3), no sheet.
    @Test func reviewAppliesTheChipAndSelectsTheFirstNotManagedRow() throws {
        let store = ScopeStore(scope: .personal, client: client, capabilities: capabilities)
        store.preload(snapshot: DesignFixtures.personal)
        ScopeOverviewView.reviewNotManaged(in: store)
        #expect(store.filter == .notManaged)
        let first = try #require(store.visibleEntries.first)
        #expect(first.isNotManaged)
        #expect(store.selection == first.id)
    }

    /// A query that hides every not-managed row is cleared, so Review lands on a row; one that matches is kept.
    @Test func reviewClearsAQueryThatHidesEveryNotManagedRow() throws {
        let store = ScopeStore(scope: .personal, client: client, capabilities: capabilities)
        store.preload(snapshot: DesignFixtures.personal)
        store.query = "no-such-skill"
        ScopeOverviewView.reviewNotManaged(in: store)
        #expect(store.query.isEmpty)
        #expect(store.selection == store.visibleEntries.first?.id && store.selection != nil)
        store.query = "caveman"
        ScopeOverviewView.reviewNotManaged(in: store)
        #expect(store.query == "caveman" && store.selection == "caveman")
    }

    // MARK: - 7. Rows from status first

    static let findingAudit =
        #"{"ok":true,"skills":[{"skill":"pdf","kind":"package","path":".claude/skills/pdf","findings":"#
        + #"[{"rule":"invisible","path":"SKILL.md","message":"invisible character"}],"commands":[],"network":[],"#
        + #""paths":[],"env":[],"scripts":[]}]}"#

    /// On the first load the rows show as soon as `status` answers; `audit` and `doctor` merge when they land.
    @Test(.timeLimit(.minutes(1))) func theFirstLoadShowsRowsFromStatusBeforeAuditAndDoctor() async {
        let scope = Scope.project(at: "/tmp/flow-order")
        let audit = Gate()
        let doctor = Gate()
        await client.json(.status, in: scope, Self.status([("pdf", "ok")]))
        await client.json(.audit, in: scope, Self.findingAudit, gate: audit)
        await client.json(.doctor(fix: false), in: scope, ScopeStoreTests.cleanDoctor, gate: doctor)
        let store = ScopeStore(scope: scope, client: client, capabilities: capabilities)
        let refresh = Task { await store.refresh() }
        await audit.arrived()
        await doctor.arrived()
        while store.snapshot == nil {
            await Task.yield()
        }
        #expect(store.snapshot?.entries.map(\.name) == ["pdf"])
        #expect(store.snapshot?.doctor == nil && store.snapshot?.entries.first?.findings.isEmpty == true)
        #expect(store.isRefreshing && store.presentation == .ready)
        await audit.open()
        await doctor.open()
        await refresh.value
        #expect(store.snapshot?.entries.first?.findings.count == 1)
        #expect(store.snapshot?.doctor != nil && !store.isRefreshing)
    }

    /// A later refresh keeps the full snapshot on screen until all three answered: findings never blink out.
    @Test(.timeLimit(.minutes(1))) func aLaterRefreshKeepsTheFullSnapshotUntilAllThreeAnswer() async {
        let scope = Scope.project(at: "/tmp/flow-order-again")
        await client.json(.status, in: scope, Self.status([("pdf", "ok")]))
        await client.json(.audit, in: scope, Self.findingAudit)
        await client.json(.doctor(fix: false), in: scope, ScopeStoreTests.cleanDoctor)
        let store = ScopeStore(scope: scope, client: client, capabilities: capabilities)
        await store.refresh()
        let audit = Gate()
        await client.json(.status, in: scope, Self.status([("pdf", "ok"), ("docx", "ok")]))
        await client.json(.audit, in: scope, Self.findingAudit, gate: audit)
        await client.json(.doctor(fix: false), in: scope, ScopeStoreTests.cleanDoctor)
        let refresh = Task { await store.refresh() }
        await audit.arrived()
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(store.snapshot?.entries.map(\.name) == ["pdf"], "the previous snapshot stays")
        #expect(store.snapshot?.entries.first?.findings.count == 1)
        await audit.open()
        await refresh.value
        #expect(store.snapshot?.entries.count == 2)
    }
}
