import SkillcaskCore
import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// The whole window over the fixture boot. `cli` comes first: the Main board's window over api exactly as
    /// the 0.9.4 CLI prints it (`DesignFixtures.apiCLI`). `main` is the Main board (api, pdf selected), `overview`
    /// the Overview board (api, nothing selected), `narrow` the 960 × 600 minimum where the Overview grid is one
    /// column: these three draw api's planned shape (`source`/`description` keys, a not managed row in a project).
    /// `personal` is My Skills. The unified toolbar is window chrome: it draws in the live app, not in an
    /// offscreen hosting view, so these renders show the columns only.
    static let shell: [Entry] = [
        Entry(id: "P3-1", state: "cli", size: CGSize(width: 1280, height: 800)) {
            AnyView(ShellSample(scope: Boot.apiScope, selection: "pdf", api: DesignFixtures.apiCLI))
        },
        Entry(id: "P3-1", state: "main", size: CGSize(width: 1280, height: 800)) {
            AnyView(ShellSample(scope: Boot.apiScope, selection: "pdf"))
        },
        Entry(id: "P3-1", state: "overview", size: CGSize(width: 1280, height: 800)) {
            AnyView(ShellSample(scope: Boot.apiScope, selection: nil))
        },
        Entry(id: "P3-1", state: "personal", size: CGSize(width: 1280, height: 800)) {
            AnyView(ShellSample(scope: .personal, selection: nil))
        },
        Entry(id: "P3-1", state: "narrow", size: CGSize(width: 960, height: 600)) {
            AnyView(ShellSample(scope: Boot.apiScope, selection: nil))
        },
    ]
}

/// The window over a fresh fixture boot, so light and dark never share a store.
private struct ShellSample: View {
    @State private var stores: Boot.Stores

    @MainActor init(scope: Scope, selection: String?, api: ScopeSnapshot = DesignFixtures.api) {
        _stores = State(initialValue: Boot.fixtures(selecting: scope, selection: selection, api: api))
    }

    var body: some View {
        MainWindow()
            .skillcaskEnvironment(
                app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
    }
}
