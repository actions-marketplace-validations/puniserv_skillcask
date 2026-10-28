import Foundation
import SkillcaskCore
import SkillcaskDomain
import Testing

@testable import SkillcaskUI

/// Boot (S13): missing, too old and ready; the scope cache; the sidebar list from Settings.
@Suite @MainActor struct AppStoreTests {
    static func settings() -> SettingsStore {
        let name = "AppStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return SettingsStore(defaults: defaults)
    }

    /// A locator that finds `/fake/skillcask` without touching the file system.
    static let found = Locator(bundled: URL(fileURLWithPath: "/fake/skillcask")) { _ in true }
    static let notFound = Locator(bundled: nil) { _ in false }

    static func versionClient(_ output: String) async -> FakeCLIClient {
        let client = FakeCLIClient()
        await client.script(.version, in: .personal, .result(stdout: output, exit: 0, lines: []))
        return client
    }

    @Test func missingBinaryIsCLIMissingWithTheSearchedPaths() async {
        let app = AppStore(settings: Self.settings(), locator: Self.notFound) { _ in FakeCLIClient() }
        await app.boot()
        guard case .missing(let searched) = app.cli else {
            Issue.record("expected .missing, got \(app.cli)")
            return
        }
        #expect(!searched.isEmpty)
        #expect(app.selectedScope == nil && app.selectedStore == nil)
    }

    @Test func tooOldBinaryIsCLITooOld() async {
        let client = await Self.versionClient("skillcask 0.8.0 (abc)\n")
        let app = AppStore(settings: Self.settings(), locator: Self.found) { _ in client }
        await app.boot()
        #expect(app.cli == .tooOld(found: Version(0, 8, 0), needs: Capabilities.minimum))
        #expect(app.store(for: .personal) == nil)
    }

    @Test func readyBinarySelectsPersonalAndCachesOneStorePerScope() async {
        let client = await Self.versionClient("skillcask 0.9.1 (abc)\n")
        let app = AppStore(settings: Self.settings(), locator: Self.found) { _ in client }
        await app.boot()
        #expect(app.cli == .ready(Capabilities(version: Version(0, 9, 1))))
        #expect(app.selectedScope == .personal)
        let first = app.store(for: .personal)
        #expect(first != nil && first === app.store(for: .personal))
        #expect(first === app.selectedStore)
        let project = Scope.project(URL(fileURLWithPath: "/tmp/p"))
        #expect(app.store(for: project) !== first)
        #expect(app.visitedStore(for: .personal) === first)
    }

    @Test func notAVersionLineIsMissing() async {
        let client = await Self.versionClient("zsh: command not found\n")
        let app = AppStore(settings: Self.settings(), locator: Self.found) { _ in client }
        await app.boot()
        #expect(app.cli == .missing(searched: ["/fake/skillcask"]))
        #expect(app.bootError == .unreadableVersion(output: "zsh: command not found\n"))
    }

    @Test func scopesListPersonalFirstThenRecents() {
        let settings = Self.settings()
        let api = URL(fileURLWithPath: "/Users/someone/work/api")
        let site = URL(fileURLWithPath: "/Users/someone/work/site")
        settings.remember(project: site)
        settings.remember(project: api)
        let app = AppStore(
            settings: settings, client: FakeCLIClient(), capabilities: Capabilities(version: Capabilities.minimum))
        #expect(app.scopes.map(\.name) == [ShellCopy.personalScope, "api", "site"])
        #expect(app.scopes.first?.subtitle == nil)
        #expect(app.scopes[1].subtitle == "/Users/someone/work/api")
        #expect(app.projects.count == 2)
    }

    @Test func openingAFolderRemembersAndSelectsIt() async {
        let settings = Self.settings()
        settings.lastScope = .personal
        let app = AppStore(
            settings: settings, client: FakeCLIClient(), capabilities: Capabilities(version: Capabilities.minimum))
        await app.boot()
        #expect(app.selectedScope == .personal)
        let folder = URL(fileURLWithPath: "/tmp/opened")
        app.open(folder: folder)
        #expect(app.selectedScope == .project(folder) && settings.lastScope == .project(folder))
        #expect(settings.recentProjects == [folder])
        app.removeFromSidebar(.project(folder))
        #expect(settings.recentProjects.isEmpty && app.selectedScope == .personal)
    }

    @Test func lastScopeIsReopenedOnlyWhenStillListed() async {
        let settings = Self.settings()
        let gone = Scope.project(URL(fileURLWithPath: "/tmp/gone"))
        settings.lastScope = gone
        let app = AppStore(
            settings: settings, client: FakeCLIClient(), capabilities: Capabilities(version: Capabilities.minimum))
        await app.boot()
        #expect(app.selectedScope == .personal)
    }

    @Test func projectsWithoutAManifestAreNotSetUp() async throws {
        let settings = Self.settings()
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "AppStoreTests-\(UUID().uuidString)")
        let ready = root.appending(path: "ready")
        let bare = root.appending(path: "bare")
        try FileManager.default.createDirectory(at: ready, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try Data("[policy]\n".utf8).write(to: ready.appending(path: "skills.toml"))
        defer { try? FileManager.default.removeItem(at: root) }
        settings.remember(project: bare)
        settings.remember(project: ready)
        let app = AppStore(
            settings: settings, client: FakeCLIClient(), capabilities: Capabilities(version: Capabilities.minimum))
        #expect(app.scopes.map(\.isSetUp) == [true, true, true], "nothing is marked before the check")
        await app.boot()
        #expect(app.item(for: .project(ready.standardizedFileURL))?.isSetUp == true)
        #expect(app.item(for: .project(bare.standardizedFileURL))?.isSetUp == false)
        #expect(app.item(for: .personal)?.isSetUp == true)
    }

    /// "Reveal skills.toml" follows the environment the children get: an override in the app's policy moves the
    /// personal manifest; a project's stays in its root.
    @Test func theManifestFollowsTheAppEnvironment() {
        let policy = EnvironmentPolicy(extraPaths: [], overrides: ["SKILLCASK_HOME": "/s"])
        let app = AppStore(
            settings: Self.settings(), client: FakeCLIClient(),
            capabilities: Capabilities(version: Capabilities.minimum),
            environment: policy)
        let base = ["HOME": "/Users/me", "XDG_CONFIG_HOME": "/x"]
        #expect(app.manifest(of: .personal, base: base).path == "/s/skills.toml")
        #expect(app.manifest(of: .project(at: "/p/app"), base: base).path == "/p/app/skills.toml")
        let plain = AppStore(
            settings: Self.settings(), client: FakeCLIClient(),
            capabilities: Capabilities(version: Capabilities.minimum))
        #expect(plain.manifest(of: .personal, base: base).path == "/x/skillcask/skills.toml")
    }

    @Test func fixtureBootShowsTheMainBoard() async {
        let stores = Boot.fixtures()
        #expect(stores.app.selectedScope == Boot.apiScope)
        #expect(stores.app.scopes.map(\.name) == [ShellCopy.personalScope, "api", "site", "infra"])
        #expect(stores.app.scopes.map(\.isSetUp) == [true, true, true, true], "the check has not run yet")
        await stores.app.boot()
        #expect(stores.app.scopes.map(\.isSetUp) == [true, true, true, false])
        let api = stores.app.selectedStore
        #expect(api?.snapshot?.entries.count == 14 && api?.selection == "pdf")
        #expect(api?.detail?.info?.package == "anthropics/skills")
        #expect(api?.detail?.text?.body.hasPrefix("## When to use") == true)
        #expect(stores.app.visitedStore(for: .personal)?.snapshot?.attention.warnings == 12)
        #expect(!Boot.usesFixtures || ProcessInfo.processInfo.environment[Boot.fixturesVariable] == "1")
    }
}
