import Foundation
import SkillcaskCore
import SkillcaskDomain
import SkillcaskUpdates

/// Builds the app-lifetime stores: the live set over the real binary, or the fixture set the render tool and
/// `swift run` with `SKILLCASK_UI_FIXTURES=1` use to show the boards' data without a CLI. Fixture mode is a
/// preview and demo mode, never on by default: `current()` picks it only when the variable is exactly `1`.
public enum Boot {
    /// The environment variable that switches `swift run` to the fixture stores.
    public static let fixturesVariable = "SKILLCASK_UI_FIXTURES"
    /// With fixtures on, the sheet or alert to open at launch over the api scope (`sheet(from:)` reads it), e.g.
    /// `SKILLCASK_UI_FIXTURES=1 SKILLCASK_UI_SHEET=update:pdf@1.4.0 swift run Skillcask`.
    public static let sheetVariable = "SKILLCASK_UI_SHEET"

    /// The three stores a scene injects with `skillcaskEnvironment`, and the client behind them.
    @MainActor public struct Stores {
        public let app: AppStore
        public let runner: ActionRunner
        public let settings: SettingsStore
        /// The seam the stores were built over, for `.environment(\.cliClient)`.
        public let client: any CLIClient
        /// The app-update check (D51); `AppUpdateStore.disabled` under fixtures.
        public var updates: AppUpdateStore = .disabled
    }

    /// The board scopes: `api` (`~/work/api`), `website` (`~/work/site`), personal.
    public static let apiScope = Scope.project(at: "~/work/api")
    /// `website` (`~/work/site`): the healthy scope of Overview-States.
    public static let websiteScope = Scope.project(at: "~/work/site")
    /// `infra-playbooks` (`~/work/infra`): the board's folder without a skills.toml.
    public static let infraScope = Scope.project(at: "~/work/infra")

    /// `SKILLCASK_UI_FIXTURES=1` in the environment: demo mode.
    public static var usesFixtures: Bool {
        ProcessInfo.processInfo.environment[fixturesVariable] == "1"
    }

    /// Fixture stores when the variable asks for them, the live stores otherwise.
    @MainActor public static func current() -> Stores {
        usesFixtures ? fixtures(sheet: sheet(from: ProcessInfo.processInfo.environment[sheetVariable])) : live()
    }

    /// The `SKILLCASK_UI_SHEET` value as a request: `update:<package>[@<version>]`, `update-all`,
    /// `add[:<query>]`, `adopt:<skill>[,<skill>…]`, `remove:<skill>[,<skill>…]`; nil for anything else.
    static func sheet(from argument: String?) -> AppStore.Sheet? {
        guard let argument, !argument.isEmpty else { return nil }
        let (verb, rest) =
            argument.firstIndex(of: ":")
            .map { (String(argument[..<$0]), String(argument[argument.index(after: $0)...])) }
            ?? (argument, "")
        let list = rest.split(separator: ",").map(String.init)
        switch verb {
        case "update" where !rest.isEmpty:
            let parts = rest.split(separator: "@", maxSplits: 1).map(String.init)
            return .update(package: parts[0], target: parts.count > 1 ? parts[1] : nil, reviewOnly: false)
        case "update-all" where rest.isEmpty: return .updateAll
        case "add": return .addSkill(query: rest.isEmpty ? nil : rest)
        case "adopt" where !list.isEmpty: return .adopt(skills: list)
        case "remove" where !list.isEmpty: return .remove(skills: list)
        default: return nil
        }
    }

    /// The real app: `UserDefaults.standard`, the located binary through `ProcessRunner`, one `MutationQueue`.
    @MainActor public static func live() -> Stores {
        let settings = SettingsStore()
        let queue = MutationQueue()
        let app = AppStore(settings: settings, queue: queue)
        let runner = ActionRunner(queue: queue)
        app.recordActivity = { [weak runner] in runner?.record($0) }
        // Off without a bundle version (`swift run`); `smoke-app.sh` passes `-appUpdates.consent declined`.
        let updates = AppUpdateStore(
            installed: AppVersion.main(), defaults: UpdateDefaults(.standard),
            context: { [weak app] in app?.updateContext })
        updates.launch()
        return Stores(
            app: app, runner: runner, settings: settings, client: UnavailableCLIClient.shared, updates: updates)
    }

    /// The window as the Main board shows it: the api scope open with pdf selected, website, the not-set-up
    /// infra-playbooks and My Skills in the sidebar with their badges, every document from `DesignFixtures`
    /// through a `FixtureCLIClient`; `sheet` opens over it. Settings
    /// live in their own defaults suite, reset on every boot, so demo runs never touch the user's settings.
    /// `manifestExists` replaces the board's check (every folder but infra-playbooks has a skills.toml). `api` is
    /// the api scope's snapshot: the boards' `DesignFixtures.api` (planned `status` keys), or `.apiCLI` for the
    /// scope exactly as the 0.9.4 CLI prints it.
    @MainActor public static func fixtures(
        selecting scope: Scope? = apiScope, selection: SkillEntry.ID? = "pdf", sheet: AppStore.Sheet? = nil,
        manifestExists: (@Sendable (URL) -> Bool)? = nil, api: ScopeSnapshot = DesignFixtures.api
    ) -> Stores {
        let suite = "skillcask.ui.fixtures"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.recentProjects = [apiScope.root, websiteScope.root, infraScope.root]
        let queue = MutationQueue()
        let client = FixtureCLIClient()
        let infra = infraScope.root
        let app = AppStore(
            settings: settings, queue: queue, client: client, capabilities: Capabilities(version: Capabilities.minimum),
            textReader: fixtureText, manifestExists: manifestExists ?? { $0 != infra })
        let runner = ActionRunner(queue: queue)
        app.recordActivity = { [weak runner] in runner?.record($0) }
        app.store(for: apiScope)?
            .preload(
                snapshot: api, selection: selection,
                detail: selection.map { SkillDetail(info: fixtureInfo(for: $0), text: fixtureText(for: $0)) })
        app.store(for: websiteScope)?.preload(snapshot: DesignFixtures.website)
        app.store(for: .personal)?.preload(snapshot: DesignFixtures.personal)
        app.selectedScope = scope
        if let sheet {
            app.request(sheet)
        }
        return Stores(app: app, runner: runner, settings: settings, client: client)
    }

    /// The SKILL.md of a fixture skill, by the last folder of its path; the boards have two.
    @Sendable static func fixtureText(at url: URL) async throws -> SkillText {
        guard let text = fixtureText(for: url.deletingLastPathComponent().lastPathComponent) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return text
    }

    static func fixtureText(for skill: String) -> SkillText? {
        switch skill {
        case "pdf": DesignFixtures.pdfText
        case "my-notes": DesignFixtures.myNotesText
        case "api-docs": DesignFixtures.apiDocsText
        default: nil
        }
    }

    static func fixtureInfo(for skill: String) -> InfoDocument? {
        switch skill {
        case "pdf": DesignFixtures.pdfInfo
        case "jira-syntax", "jira-communication": DesignFixtures.jiraPackageInfo
        case "legacy-lint": DesignFixtures.legacyLintInfo
        case "safe-refactor": DesignFixtures.safeRefactorInfo
        case "commit-message": DesignFixtures.commitMessageInfo
        case "my-notes": DesignFixtures.myNotesInfo
        default: nil
        }
    }
}
