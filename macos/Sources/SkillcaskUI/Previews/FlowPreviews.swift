import Foundation
import SkillcaskCore
import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// The Flow-F1 and F5 walk fixes. The Find Projects sheet at `FindProjectsSheet.size`: `findLoading`
    /// while `projects` runs, `findFound` (three folders, one already in the sidebar), `findAllAdded` (every folder
    /// already listed: Close alone), `findNone` (no hit) and `findFailed` (the command failed). The window at 1280 × 800: `setUpBefore` (infra-playbooks without
    /// skills.toml, the Set Up block), `setUpAfter` (the same folder once Set Up ran: the row drops "Not set up",
    /// the list shows "No skills yet · Add Skill…"), `launching` (Flow-F1 step 0: the CLI not located yet, My
    /// Skills dimmed, the columns empty) and `reviewNotManaged` (first launch after the banner's Review: the Not
    /// managed chip and its first row selected).
    static let flow: [Entry] = [
        sheet("findLoading") { FindProjectsSample(phase: .loading) },
        sheet("findFound") { FindProjectsSample(phase: .found(FindProjectsSample.found)) },
        sheet("findAllAdded") {
            FindProjectsSample(
                phase: .found(
                    FindProjectsPlan(
                        found: [Boot.apiScope.root, Boot.websiteScope.root], recents: FindProjectsSample.recents)))
        },
        sheet("findNone") { FindProjectsSample(phase: .found(FindProjectsPlan(found: [], recents: []))) },
        sheet("findFailed") { FindProjectsSample(phase: .failed(FindProjectsSample.failure)) },
        window("setUpBefore") { WindowSample(.setUpBefore) },
        window("setUpAfter") { WindowSample(.setUpAfter) },
        window("launching") { WindowSample(.launching) },
        window("reviewNotManaged") { WindowSample(.reviewNotManaged) },
    ]

    private static func sheet(
        _ state: String, _ make: @escaping @MainActor @Sendable () -> FindProjectsSample
    ) -> Entry {
        Entry(id: "P3-16", state: state, size: FindProjectsSheet.size) { AnyView(make()) }
    }

    private static func window(_ state: String, _ make: @escaping @MainActor @Sendable () -> WindowSample) -> Entry {
        Entry(id: "P3-16", state: state, size: CGSize(width: 1280, height: 800)) { AnyView(make()) }
    }
}

/// The Find Projects sheet over the fixture stores, with its result already in (no command runs).
private struct FindProjectsSample: View {
    let phase: FindProjectsSheet.Phase

    static let root = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "work")
    /// api is already in the fixture sidebar; billing and docs-site are new.
    static let found = FindProjectsPlan(
        found: [Boot.apiScope.root, root.appending(path: "billing"), root.appending(path: "docs-site")],
        recents: recents)
    /// The fixture sidebar's projects.
    static let recents = [Boot.apiScope.root, Boot.websiteScope.root, Boot.infraScope.root]
    static let failure = CLIError.failed(
        code: .problem, message: "~/work/archive: permission denied", hint: nil, stderr: "")

    var body: some View {
        let stores = Boot.fixtures(selecting: .personal, selection: nil)
        FindProjectsSheet(root: Self.root, onClose: {}, phase: phase)
            .skillcaskEnvironment(
                app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
    }
}

/// The window over a fresh fixture boot in one of the flow's states.
private struct WindowSample: View {
    enum Kind {
        case setUpBefore
        case setUpAfter
        case launching
        case reviewNotManaged
    }

    @State private var stores: Boot.Stores

    @MainActor init(_ kind: Kind) {
        _stores = State(initialValue: Self.stores(kind))
    }

    @MainActor private static func stores(_ kind: Kind) -> Boot.Stores {
        switch kind {
        case .setUpBefore:
            let stores = Boot.fixtures(selecting: Boot.infraScope, selection: nil)
            stores.app.preloadSetUp()
            return stores
        case .setUpAfter:
            let stores = Boot.fixtures(selecting: Boot.infraScope, selection: nil, manifestExists: { _ in true })
            stores.app.preloadSetUp()
            stores.app.store(for: Boot.infraScope)?.preload(snapshot: DesignFixtures.emptyAfterSetUp)
            return stores
        case .launching:
            let suite = "skillcask.ui.p3-16.launching"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            let settings = SettingsStore(defaults: defaults)
            let queue = MutationQueue()
            // The CLI never answers `--version`, so the window stays where Flow-F1 step 0 draws it.
            let app = AppStore(
                settings: settings, queue: queue,
                locator: Locator(bundled: URL(fileURLWithPath: "/fixture/skillcask")) { _ in true },
                makeClient: { _ in SilentCLIClient() })
            return Boot.Stores(
                app: app, runner: ActionRunner(queue: queue), settings: settings, client: SilentCLIClient())
        case .reviewNotManaged:
            let stores = Boot.fixtures(selecting: .personal, selection: nil)
            stores.settings.recentProjects = []
            if let store = stores.app.store(for: .personal) {
                ScopeOverviewView.reviewNotManaged(in: store)
            }
            return stores
        }
    }

    var body: some View {
        MainWindow()
            .skillcaskEnvironment(
                app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
    }
}

/// A CLI that has not answered yet: every run waits until it is cancelled. Previews only.
private struct SilentCLIClient: CLIClient {
    func run(
        _ invocation: Invocation, onLine: @escaping @Sendable (OutputLine) -> Void
    ) async throws(CLIError) -> RunResult {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        throw .cancelled
    }
}

#Preview("FindProjectsSheet found, light") {
    FindProjectsSample(phase: .found(FindProjectsSample.found))
}

#Preview("MainWindow after Set Up, dark") {
    WindowSample(.setUpAfter)
        .preferredColorScheme(.dark)
}
