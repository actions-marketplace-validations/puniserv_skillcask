import SkillcaskCore
import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// P3-4: the Scope Overview in the detail column (720 × 900) over the fixture boot, one state per Overview and
    /// Overview-States panel: `attention` (api, the Overview board), `healthy` (website), `loading` (api before
    /// its first status), `noProjects` (My Skills with an empty sidebar), `notSetUp` (infra-playbooks) and
    /// `repaired` (api after Repair, Health-States "After Repair" as a card).
    static let overview: [Entry] = [
        entry("attention") { OverviewSample(.attention) },
        entry("healthy") { OverviewSample(.healthy) },
        entry("loading") { OverviewSample(.loading) },
        entry("noProjects") { OverviewSample(.noProjects) },
        entry("notSetUp") { OverviewSample(.notSetUp) },
        entry("repaired") { OverviewSample(.repaired) },
    ]

    private static func entry(_ state: String, _ make: @escaping @MainActor @Sendable () -> OverviewSample) -> Entry {
        Entry(id: "P3-4", state: state, size: CGSize(width: 720, height: 900)) { AnyView(make()) }
    }
}

/// The Scope Overview of one fixture scope, over a fresh fixture boot so light and dark never share a store.
private struct OverviewSample: View {
    enum Kind {
        case attention
        case healthy
        case loading
        case noProjects
        case notSetUp
        case repaired
    }

    @State private var stores: Boot.Stores
    @State private var store: ScopeStore?
    private let isSetUp: Bool

    @MainActor init(_ kind: Kind) {
        let stores = Boot.fixtures(selecting: Boot.apiScope, selection: nil)
        let app = stores.app
        let capabilities = Capabilities(version: Capabilities.minimum)
        var store: ScopeStore?
        switch kind {
        case .attention:
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
        }
        _stores = State(initialValue: stores)
        _store = State(initialValue: store)
        isSetUp = kind != .notSetUp
    }

    var body: some View {
        if let store {
            ScopeOverviewView(store: store, isSetUp: isSetUp)
                .skillcaskEnvironment(
                    app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
        }
    }
}
