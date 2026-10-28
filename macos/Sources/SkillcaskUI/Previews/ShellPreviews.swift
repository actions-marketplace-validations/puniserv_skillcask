import SkillcaskCore
import SwiftUI

extension PreviewRegistry {
    /// P3-1: the whole window over the fixture boot. `main` is the Main board (api, pdf selected), `overview` the
    /// Overview board (api, nothing selected), `personal` My Skills, `narrow` the 960 × 600 minimum where the
    /// Overview grid is one column. The unified toolbar is window chrome: it draws in the live app, not in an
    /// offscreen hosting view, so these renders show the columns only.
    static let shell: [Entry] = [
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

    @MainActor init(scope: Scope, selection: String?) {
        _stores = State(initialValue: Boot.fixtures(selecting: scope, selection: selection))
    }

    var body: some View {
        MainWindow()
            .skillcaskEnvironment(
                app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
    }
}
