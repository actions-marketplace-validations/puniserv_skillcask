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

    /// The sheets the toolbar and menus ask for. Nothing presents them yet: the Add Skill (P3-5), Review Update
    /// (P3-6), Adopt and Remove (P3-8) tasks add `.sheet(item:)` over `MainWindow`; until then the request is
    /// recorded here and cleared by the next one.
    public enum Sheet: Identifiable, Hashable, Sendable {
        case addSkill
        case updateAll
        case update(package: String)
        case remove(skills: [String])
        case adopt(skill: String)

        public var id: String {
            switch self {
            case .addSkill: "add"
            case .updateAll: "update-all"
            case .update(let package): "update-\(package)"
            case .remove(let skills): "remove-\(skills.joined(separator: ","))"
            case .adopt(let skill): "adopt-\(skill)"
            }
        }
    }

    /// The settings the sidebar (recents) and the boot (binary path, open-at-launch) read.
    public let settings: SettingsStore
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
    /// The sheet the toolbar or a menu asked for; see `Sheet`.
    public var sheet: Sheet?
    /// Where the located binary is, for Settings › General.
    public private(set) var binary: Locator.Choice?
    @ObservationIgnored private var client: (any CLIClient)?
    @ObservationIgnored private var stores: [Scope: ScopeStore] = [:]

    /// The live app: locates the binary on `boot()` and talks to it through `makeClient`.
    public init(
        settings: SettingsStore, queue: MutationQueue = MutationQueue(), locator: Locator = Locator(),
        makeClient: @escaping @Sendable (URL) -> any CLIClient = { ProcessRunner(executable: $0) },
        textReader: @escaping ScopeStore.TextReader = ScopeStore.readText,
        manifestExists: @escaping @Sendable (URL) -> Bool = AppStore.manifestOnDisk
    ) {
        self.settings = settings
        self.queue = queue
        self.locator = locator
        self.makeClient = makeClient
        self.textReader = textReader
        self.manifestExists = manifestExists
    }

    /// A ready app over a known client: tests and the fixture boot skip the location and the version gate.
    public init(
        settings: SettingsStore, queue: MutationQueue = MutationQueue(), client: any CLIClient,
        capabilities: Capabilities, textReader: @escaping ScopeStore.TextReader = ScopeStore.readText,
        manifestExists: @escaping @Sendable (URL) -> Bool = AppStore.manifestOnDisk
    ) {
        self.settings = settings
        self.queue = queue
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
        stores[scope] = store
        return store
    }

    /// The store of `scope` only when the scope was visited: the sidebar badge reads this.
    public func visitedStore(for scope: Scope) -> ScopeStore? {
        stores[scope]
    }

    /// The sidebar row of `scope`; nil when the scope is not listed.
    public func item(for scope: Scope) -> ScopeItem? {
        scopes.first { $0.scope == scope }
    }

    // MARK: - Boot

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
        let locator = locator
        let configured = settings.binaryPath
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
        switch located {
        case .failure(let error):
            fail(error, searched: [])
            return
        case .success(let choice):
            binary = choice
            let client = makeClient(choice.url)
            do {
                let probe = try Invocation(
                    .version, in: .personal, capabilities: Capabilities(version: Capabilities.minimum))
                let capabilities = try await client.capabilities(via: probe)
                self.client = client
                cli = .ready(capabilities)
            } catch {
                fail(error, searched: [choice.url.path])
            }
        }
    }

    private func fail(_ error: CLIError, searched: [String]) {
        bootError = error
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
