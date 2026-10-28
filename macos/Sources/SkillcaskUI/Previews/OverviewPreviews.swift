import SkillcaskCore
import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// The Scope Overview in the detail column (720 × 1300: tall enough for the Agents card under the Health
    /// card's 8 problems) over the fixture boot, one state per Overview and
    /// Overview-States panel: `attention` (api, the Overview board), `healthy` (website), `loading` (api before
    /// its first status), `noProjects` (My Skills with an empty sidebar), `notSetUp` (infra-playbooks) and
    /// `repaired` (api after Repair, Health-States "After Repair" as a card). `cli` comes first: `attention` over
    /// api exactly as the 0.9.1 CLI prints it (`DesignFixtures.apiCLI`); `attention`, `loading` and `repaired`
    /// draw api's planned shape (`source`/`description` keys, caveman not managed in a project scope).
    static let overview: [Entry] = [
        entry("cli") { OverviewSample(.cli) },
        entry("attention") { OverviewSample(.attention) },
        entry("healthy") { OverviewSample(.healthy) },
        entry("loading") { OverviewSample(.loading) },
        entry("noProjects") { OverviewSample(.noProjects) },
        entry("notSetUp") { OverviewSample(.notSetUp) },
        entry("repaired") { OverviewSample(.repaired) },
        // A refresh that read `status` but not `audit` and `doctor`: the header's warning strip, closed and with its
        // Details open. Invented (no board draws it).
        entry("partialRefresh") { OverviewSample(.partialRefresh) },
        entry("partialRefreshDetails") { OverviewSample(.partialRefreshDetails) },
    ]

    private static func entry(_ state: String, _ make: @escaping @MainActor @Sendable () -> OverviewSample) -> Entry {
        Entry(id: "P3-4", state: state, size: CGSize(width: 720, height: 1300)) { AnyView(make()) }
    }
}

/// The Scope Overview of one fixture scope, over a fresh fixture boot so light and dark never share a store.
private struct OverviewSample: View {
    enum Kind {
        case cli
        case attention
        case healthy
        case loading
        case noProjects
        case notSetUp
        case repaired
        case partialRefresh
        case partialRefreshDetails
    }

    @State private var stores: Boot.Stores
    @State private var store: ScopeStore?
    private let isSetUp: Bool
    private let showsPartialDetails: Bool

    @MainActor init(_ kind: Kind) {
        let stores = Boot.fixtures(
            selecting: Boot.apiScope, selection: nil, api: kind == .cli ? DesignFixtures.apiCLI : DesignFixtures.api)
        let app = stores.app
        let capabilities = Capabilities(version: Capabilities.minimum)
        var store: ScopeStore?
        switch kind {
        case .cli, .attention:
            store = app.store(for: Boot.apiScope)
        case .healthy:
            store = app.store(for: Boot.websiteScope)
        case .loading:
            store = ScopeStore(scope: Boot.apiScope, client: stores.client, capabilities: capabilities)
        case .noProjects:
            stores.settings.recentProjects = []
            store = app.store(for: .personal)
        case .notSetUp:
            store = app.store(for: Boot.infraScope)
        case .repaired:
            let repaired = ScopeStore(scope: Boot.apiScope, client: stores.client, capabilities: capabilities)
            repaired.preload(snapshot: DesignFixtures.apiRepaired)
            store = repaired
        case .partialRefresh, .partialRefreshDetails:
            let partial = app.store(for: Boot.apiScope)
            partial?.preload(partialFailure: DesignFixtures.partialFailure)
            store = partial
        }
        showsPartialDetails = kind == .partialRefreshDetails
        _stores = State(initialValue: stores)
        _store = State(initialValue: store)
        isSetUp = kind != .notSetUp
    }

    var body: some View {
        if let store {
            ScopeOverviewView(store: store, isSetUp: isSetUp, showsPartialDetails: showsPartialDetails)
                .skillcaskEnvironment(
                    app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
        }
    }
}
