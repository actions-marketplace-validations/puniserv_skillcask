import Foundation
import Observation
import SkillcaskCore
import SkillcaskDomain

/// The window's root state (ADR §3): whether the CLI is usable, the scopes in the sidebar, which one is selected,
/// and one `ScopeStore` per visited scope. Lives as long as the app; never recreated on a scope switch, so
/// switching back is instant and the previous snapshot shows while it refreshes.
@MainActor @Observable public final class AppStore {
    /// Where the app stands with the binary (S13): a sheet covers everything until `.ready`.
    public enum CLIState: Hashable, Sendable {
        case locating
        case missing(searched: [String])
        case tooOld(found: Version, needs: Version)
        case ready(Capabilities)
    }

    /// One sidebar row: the scope, its name and the path shown under it (nil for the personal row, which the
    /// board draws on one line).
    public struct ScopeItem: Identifiable, Hashable, Sendable {
        public let scope: Scope
        /// "My Skills", or the project's folder name.
        public let name: String
        /// The project's `~`-abbreviated path; nil for the personal row (one line on the board).
        public let subtitle: String?
        /// A project folder has a skills.toml (ADR §5: else `.noManifest`, the Set Up block); always true for the
        /// personal scope here (its `init -g` state is only known from `status -g`).
        public let isSetUp: Bool

        public var id: Scope { scope }

        public init(scope: Scope, name: String, subtitle: String?, isSetUp: Bool = true) {
            self.scope = scope
            self.name = name
            self.subtitle = subtitle
            self.isSetUp = isSetUp
        }
    }

    /// What the toolbar, menus, rows and detail ask the window to present over the selected scope, through
    /// `request(_:)`. `MainWindow` shows every case but `.remove` as a sheet through `SheetHost` (`presentedSheet`);
    /// `.remove` is the system alert of S10 (`removal`). Each case carries what its destination needs to open:
    /// Review Update (S7, P3-8), Add Skill (S8, P3-9), Adopt and Remove (S9, S10, P3-10).
    public enum Sheet: Identifiable, Hashable, Sendable {
        /// Review one package's update. `target` is the version the row or strip offered; nil lets `diff` choose
        /// the newest inside the range. `reviewOnly` is set when the tag moved (Q3): the sheet then never makes
        /// Update its default button.
        case update(package: String, target: String?, reviewOnly: Bool)
        /// Review every package with an update inside its range.
        case updateAll
        /// Search and add; `query` pre-fills the field ("Find “…” in sources").
        case addSkill(query: String?)
        /// Adopt not-managed skills: one from a row or the detail, several from the Not managed filter.
        case adopt(skills: [String])
        /// Remove skills: a system alert, not a sheet.
        case remove(skills: [String])

        public var id: String {
            switch self {
            case .update(let package, let target, _): "update-\(package)-\(target ?? "")"
            case .updateAll: "update-all"
            case .addSkill(let query): "add-\(query ?? "")"
            case .adopt(let skills): "adopt-\(skills.joined(separator: ","))"
            case .remove(let skills): "remove-\(skills.joined(separator: ","))"
            }
        }

        /// Presented as an alert rather than a sheet.
        public var isAlert: Bool {
            if case .remove = self { true } else { false }
        }

        /// Update… for `entry`: its package (the skill id for a package-less row), the version it offers, and
        /// review-only when its tag moved (`DetailActions.isTagMoved`).
        public static func update(for entry: SkillEntry) -> Sheet {
            .update(
                package: entry.package ?? entry.id, target: DetailActions.updateTarget(of: entry),
                reviewOnly: DetailActions.isTagMoved(entry))
        }

        /// Review one package from a place that knows no entry (Overview's Updates card): `diff` chooses.
        public static func update(package: String) -> Sheet {
            .update(package: package, target: nil, reviewOnly: false)
        }
    }

    /// A request on screen: the sheet or alert, the scope it was asked for (pinned, so switching the sidebar or
    /// Open Recent never rebinds it), and an identity so a close clears only its own presentation.
    public struct Presentation: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let sheet: Sheet
        public let scope: Scope
    }

    /// The settings the sidebar (recents) and the boot (binary path, open-at-launch) read.
    public let settings: SettingsStore
    /// The environment every child gets: the live client reads it at every spawn (through `environmentSource`),
    /// and `manifest(of:)` and `configFile()` resolve through it, so a Settings override reaches all three from the
    /// next run on. Starts from the policy given plus Settings › Advanced's table; `setEnvironmentVariables(_:)`
    /// changes it.
    public private(set) var environment: EnvironmentPolicy {
        didSet { environmentSource.policy = environment }
    }
    /// The live policy `ProcessRunner` reads; shared by reference so no client needs rebuilding.
    @ObservationIgnored private let environmentSource: EnvironmentSource
    /// The policy the app was built with, before Settings' table: a table edit rebuilds `environment` from it, so
    /// removing a row restores a base override of the same name rather than wiping it.
    @ObservationIgnored private let baseEnvironment: EnvironmentPolicy
    /// Settings' CLI-side state (S14: skills.sh in config.toml, the GitHub token); app-lifetime, so this session's
    /// sign-in survives closing the Settings window.
    public let cliSettings = CLISettingsStore()
    /// The one mutation queue of the app, shared with `ActionRunner`.
    public let queue: MutationQueue
    private let locator: Locator
    private let makeClient: @Sendable (URL) -> any CLIClient
    private let textReader: ScopeStore.TextReader
    private let manifestExists: @Sendable (URL) -> Bool

    /// Whether `root/skills.toml` exists on disk: the live check.
    public static let manifestOnDisk: @Sendable (URL) -> Bool = {
        FileManager.default.fileExists(atPath: $0.appending(path: "skills.toml").path)
    }

    // MARK: - State

    public private(set) var cli: CLIState = .locating
    /// Why the last boot failed, for the onboarding sheet's Details (S13).
    public private(set) var bootError: CLIError?
    /// The last failure of an app-level read (Find Projects); a later banner shows it.
    public var lastError: CLIError?
    /// Project roots without a skills.toml, from the last manifest check (`refreshSetUp`).
    public private(set) var notSetUp: Set<URL> = []
    public var selectedScope: Scope? {
        didSet { settings.lastScope = selectedScope }
    }
    /// The sheet or alert on screen; see `request(_:)` and `dismiss(_:)`.
    public private(set) var presentation: Presentation?
    /// A detection failed and none has succeeded since: the S13 onboarding sheet stays up, also while Try Again
    /// or Locate… re-detects (`cli` is `.locating` then), until the CLI is ready.
    public private(set) var detectionFailed = false
    /// Try Again or Locate… is running: a second press while one runs is ignored, so a double click detects once.
    /// Set on the main actor before the first `await`, so two presses can never both pass the check.
    public private(set) var isRedetecting = false

    /// The S13 onboarding sheet covers the window (P3-12): the CLI is missing or too old, or being re-detected
    /// after such a failure.
    public var isOnboarding: Bool {
        detectionFailed && !isReady
    }

    /// A sheet, the Remove alert or the onboarding sheet is up: every other request is refused and the commands
    /// that make one are disabled.
    public var isPresenting: Bool {
        presentation != nil || isOnboarding
    }

    /// The presentation when it is a sheet, for `.sheet(item:)`.
    public var presentedSheet: Presentation? {
        presentation.flatMap { $0.sheet.isAlert ? nil : $0 }
    }

    /// The presentation when it is the Remove alert.
    public var removal: Presentation? {
        presentation.flatMap { $0.sheet.isAlert ? $0 : nil }
    }

    /// The one entry point for a sheet or the alert, over the selected scope. Refused (false) while another is up,
    /// so a menu shortcut can never replace a running sheet or pop the alert over it, and without a scope or its
    /// store (the CLI not ready).
    @discardableResult public func request(_ sheet: Sheet) -> Bool {
        guard !isPresenting, let scope = selectedScope, store(for: scope) != nil else { return false }
        presentation = Presentation(id: UUID(), sheet: sheet, scope: scope)
        return true
    }

    /// Closes the sheet or alert whose pinned scope has no store any more (the CLI went away), so `isPresenting`
    /// cannot stick behind an empty sheet or an alert that never shows. `MainWindow` calls it whenever the
    /// presentation or the CLI state changes.
    public func dropOrphanedPresentation() {
        if let orphan = Self.orphan(presentation, hasStore: { store(for: $0) != nil }) {
            dismiss(orphan)
        }
    }

    /// `presentation` when its scope has no store; nil otherwise.
    nonisolated static func orphan(_ presentation: Presentation?, hasStore: (Scope) -> Bool) -> Presentation? {
        presentation.flatMap { hasStore($0.scope) ? nil : $0 }
    }

    /// Closes `presentation` if it is still the one on screen; a stale close (a late `onSuccess`) does nothing.
    public func dismiss(_ presentation: Presentation) {
        if self.presentation?.id == presentation.id {
            self.presentation = nil
        }
    }
    /// Where the located binary is, for Settings › General.
    public private(set) var binary: Locator.Choice?
    @ObservationIgnored private var client: (any CLIClient)?
    @ObservationIgnored private var stores: [Scope: ScopeStore] = [:]
    /// Where every scope store records the reads the user starts (S15): `ActionRunner.record(_:)`, set by `Boot`.
    @ObservationIgnored public var recordActivity: ActionRunner.ActivitySink?

    /// The live app: locates the binary on `boot()` and talks to it through `makeClient`.
    public init(
        settings: SettingsStore, queue: MutationQueue = MutationQueue(), locator: Locator = Locator(),
        environment: EnvironmentPolicy = .default, makeClient: (@Sendable (URL) -> any CLIClient)? = nil,
        textReader: @escaping ScopeStore.TextReader = ScopeStore.readText,
        manifestExists: @escaping @Sendable (URL) -> Bool = AppStore.manifestOnDisk
    ) {
        self.settings = settings
        self.queue = queue
        self.locator = locator
        let policy = Self.policy(environment, with: settings)
        let source = EnvironmentSource(policy)
        self.environment = policy
        environmentSource = source
        baseEnvironment = environment
        self.makeClient = makeClient ?? { ProcessRunner(executable: $0, source: source) }
        self.textReader = textReader
        self.manifestExists = manifestExists
    }

    /// A ready app over a known client: tests and the fixture boot skip the location and the version gate.
    public init(
        settings: SettingsStore, queue: MutationQueue = MutationQueue(), client: any CLIClient,
        capabilities: Capabilities, environment: EnvironmentPolicy = .default,
        textReader: @escaping ScopeStore.TextReader = ScopeStore.readText,
        manifestExists: @escaping @Sendable (URL) -> Bool = AppStore.manifestOnDisk
    ) {
        self.settings = settings
        self.queue = queue
        let policy = Self.policy(environment, with: settings)
        self.environment = policy
        environmentSource = EnvironmentSource(policy)
        baseEnvironment = environment
        locator = Locator()
        makeClient = { _ in client }
        self.textReader = textReader
        self.manifestExists = manifestExists
        self.client = client
        cli = .ready(capabilities)
    }

    // MARK: - Derived

    /// Personal first, then the recent projects in order (Settings).
    public var scopes: [ScopeItem] {
        [ScopeItem(scope: .personal, name: ShellCopy.personalScope, subtitle: nil)]
            + settings.recentProjects.map {
                ScopeItem(
                    scope: .project($0), name: Self.name(of: $0), subtitle: Self.subtitle(of: $0),
                    isSetUp: !notSetUp.contains($0.standardizedFileURL))
            }
    }

    /// The project rows alone, in sidebar order.
    public var projects: [ScopeItem] {
        scopes.filter { !$0.scope.isPersonal }
    }

    /// The CLI was located and passed the version gate.
    public var isReady: Bool {
        if case .ready = cli { true } else { false }
    }

    /// The located CLI's capabilities; nil until ready.
    public var capabilities: Capabilities? {
        if case .ready(let capabilities) = cli { capabilities } else { nil }
    }

    /// The selected scope's store, once the CLI is ready.
    public var selectedStore: ScopeStore? {
        selectedScope.flatMap { store(for: $0) }
    }

    /// The store of `scope`, created on first use and kept: nil until the CLI is ready.
    public func store(for scope: Scope) -> ScopeStore? {
        guard let client, let capabilities else { return nil }
        if let store = stores[scope] {
            return store
        }
        let store = ScopeStore(
            scope: scope, client: client, capabilities: capabilities, settings: settings, queue: queue,
            textReader: textReader)
        store.recordActivity = recordActivity
        stores[scope] = store
        return store
    }

    /// The store of `scope` only when the scope was visited: the sidebar badge reads this.
    public func visitedStore(for scope: Scope) -> ScopeStore? {
        stores[scope]
    }

    // MARK: - Settings

    /// `environment` with Settings' table on top of its overrides.
    private static func policy(_ environment: EnvironmentPolicy, with settings: SettingsStore) -> EnvironmentPolicy {
        var policy = environment
        policy.overrides.merge(settings.environmentOverrides) { _, table in table }
        return policy
    }

    /// Settings › Advanced: stores the table and applies the rows the policy allows to every run that starts
    /// after this call (running ones keep the environment they started with).
    public func setEnvironmentVariables(_ rows: [SettingsStore.EnvironmentVariable]) {
        settings.environmentVariables = rows
        environment = Self.policy(baseEnvironment, with: settings)
    }

    /// The CLI's config.toml, resolved in the children's environment (Settings › Advanced, Open config.toml).
    public func configFile(base: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        CLIConfig.file(
            environment: environment.environment(from: base), home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// What Settings' own commands (skills.sh, `auth`) run with; nil until the CLI is ready.
    public var cliContext: CLISettingsStore.Context? {
        guard let client, let capabilities else { return nil }
        return CLISettingsStore.Context(client: client, capabilities: capabilities, configFile: configFile())
    }

    /// Settings › General, "Use the detected one": forgets the chosen binary and detects again (bundled, then
    /// `PATH`). The scope stores built over the old client are dropped so every later run uses the new one.
    public func useDetectedBinary() async {
        guard !isRedetecting else { return }
        isRedetecting = true
        defer { isRedetecting = false }
        settings.binaryPath = nil
        client = nil
        stores.removeAll()
        cli = .locating
        await boot()
    }

    /// The skills.toml the CLI reads for `scope`, resolved in the children's environment (`environment`).
    public func manifest(of scope: Scope, base: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        scope.manifest(environment: environment.environment(from: base))
    }

    /// The sidebar row of `scope`; nil when the scope is not listed.
    public func item(for scope: Scope) -> ScopeItem? {
        scopes.first { $0.scope == scope }
    }

    // MARK: - Boot

    /// Try Again (S13): detects again unless Try Again or Locate… is already running.
    public func tryAgain() async {
        guard !isRedetecting else { return }
        isRedetecting = true
        defer { isRedetecting = false }
        await boot()
    }

    /// Locate → `--version` → `Capabilities`, then the scope Settings asks for. Runs again after "Try again" or a
    /// binary path change; a ready app only re-selects.
    public func boot() async {
        if !isReady {
            await locate()
        }
        guard isReady else { return }
        await refreshSetUp()
        if selectedScope == nil {
            selectedScope = initialScope
        }
    }

    private func locate() async {
        cli = .locating
        bootError = nil
        switch await find(configured: settings.binaryPath) {
        case .failure(let error):
            fail(error, searched: [])
            return
        case .success(let choice):
            binary = choice
            do {
                let (client, capabilities) = try await probe(choice.url)
                self.client = client
                cli = .ready(capabilities)
                detectionFailed = false
            } catch {
                fail(error, searched: [choice.url.path])
            }
        }
    }

    /// Locate… (S13) and Settings' Choose…: `url` goes through the same locator and `--version` gate as a boot.
    /// Only a binary that passes is written to Settings (`binaryPath`) and boots the app, and the scope stores are
    /// rebuilt over it; a refused one leaves Settings and `cli` as they were. Returns why it was refused, nil when the app is ready, `.cancelled` when a detection was already
    /// running. `url` is stored as given (the symlink the user picked, not the file it resolves to), so a Homebrew
    /// upgrade that moves the Cellar target keeps working.
    @discardableResult public func locate(executable url: URL) async -> CLIError? {
        guard !isRedetecting else { return .cancelled }
        isRedetecting = true
        defer { isRedetecting = false }
        let path = url.path
        switch await find(configured: path) {
        case .failure(let error):
            return error
        case .success(let choice):
            do {
                let (client, capabilities) = try await probe(choice.url)
                settings.binaryPath = path
                binary = choice
                self.client = client
                // Built over the old client: dropped so every open scope's next command runs the chosen tool.
                stores.removeAll()
                bootError = nil
                cli = .ready(capabilities)
                detectionFailed = false
            } catch {
                return error
            }
        }
        await boot()
        return nil
    }

    /// `Locator.locate` off the main actor: the file checks never block the window.
    private func find(configured: String?) async -> Result<Locator.Choice, CLIError> {
        let locator = locator
        let located: Result<Locator.Choice, CLIError> =
            await Task.detached {
                do {
                    return .success(try locator.locate(configured: configured))
                } catch let error as CLIError {
                    return .failure(error)
                } catch {
                    return .failure(.launchFailed(String(describing: error)))
                }
            }
            .value
        return located
    }

    /// `--version` through the gate on a client for `url`.
    private func probe(_ url: URL) async throws(CLIError) -> (any CLIClient, Capabilities) {
        let client = makeClient(url)
        let probe = try Invocation(.version, in: .personal, capabilities: Capabilities(version: Capabilities.minimum))
        return (client, try await client.capabilities(via: probe))
    }

    private func fail(_ error: CLIError, searched: [String]) {
        bootError = error
        detectionFailed = true
        switch error {
        case .binaryMissing(let paths): cli = .missing(searched: paths)
        case .tooOld(let found, let needs): cli = .tooOld(found: found, needs: needs)
        default: cli = .missing(searched: searched)
        }
    }

    private var initialScope: Scope {
        switch settings.openAtLaunch {
        case .personal:
            return .personal
        case .lastScope:
            if let last = settings.lastScope, scopes.contains(where: { $0.scope == last }) {
                return last
            }
            return .personal
        }
    }

    // MARK: - Scopes

    /// Adds `folder` to the sidebar (first in the recents) and opens it.
    public func open(folder: URL) {
        settings.remember(project: folder)
        selectedScope = .project(folder.standardizedFileURL)
        Task { await refreshSetUp() }
    }

    /// Which recent projects have a skills.toml, through `manifestExists` off the main actor (SUI-20), so the
    /// sidebar can draw the not-set-up rows and the detail the Set Up block. Runs on boot, after Open Folder…
    /// and after Find Projects; the fixture boot injects a check that never touches the disk.
    public func refreshSetUp() async {
        let roots = settings.recentProjects.map(\.standardizedFileURL)
        let exists = manifestExists
        let missing = await Task.detached { Set(roots.filter { !exists($0) }) }.value
        notSetUp = missing
    }

    /// Drops a project from the sidebar and forgets its store; the personal row cannot be removed.
    public func removeFromSidebar(_ scope: Scope) {
        guard case .project(let url) = scope else { return }
        settings.forget(project: url)
        stores.removeValue(forKey: scope)
        if selectedScope == scope {
            selectedScope = .personal
        }
    }

    /// `projects --json -- <root>`: every folder under `root` with a skills.toml joins the sidebar.
    public func findProjects(under root: URL) async {
        guard let client, let capabilities else { return }
        do {
            let invocation = try Invocation(.projects(roots: [root]), in: .project(root), capabilities: capabilities)
            let document = try await client.document(ProjectsDocument.self, for: invocation)
            for project in document.projects.reversed() {
                settings.remember(project: URL(fileURLWithPath: (project.path as NSString).expandingTildeInPath))
            }
            await refreshSetUp()
        } catch {
            lastError = error
        }
    }

    // MARK: - Names

    /// The sidebar name of a project: its folder name.
    public nonisolated static func name(of root: URL) -> String {
        root.lastPathComponent
    }

    /// The path under a project's name, with the home directory as `~`.
    public nonisolated static func subtitle(of root: URL) -> String {
        (root.path as NSString).abbreviatingWithTildeInPath
    }
}
