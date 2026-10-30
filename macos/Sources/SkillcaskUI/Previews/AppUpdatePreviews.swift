import Foundation
import SkillcaskCore
import SkillcaskUpdates
import SwiftUI

extension PreviewRegistry {
    /// U1, the app-update card (D51): `available`, `consent` and `awaiting` alone at the sidebar's 220 pt on its
    /// ground, and `window`, the whole window over the fixture boot with the available card above Open Folder….
    /// Versions are data: the app at 0.10.2, 0.10.3 released.
    static let appUpdate: [Entry] = [
        card("available", height: 104, .available(AppUpdateSample.latest)),
        card("consent", height: 140, .consentPrompt),
        card("awaiting", height: 84, .awaitingRelaunch),
        Entry(id: "U1", state: "window", size: CGSize(width: 1280, height: 800)) {
            AnyView(AppUpdateWindowSample())
        },
    ]

    private static func card(_ state: String, height: CGFloat, _ card: UpdateCard) -> Entry {
        Entry(id: "U1", state: state, size: CGSize(width: Size.sidebarWidth, height: height)) {
            AnyView(
                AppUpdateCard(card: card, installed: AppUpdateSample.installed)
                    .padding(AppUpdateCard.padding)
                    .frame(width: Size.sidebarWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color.surfaceSidebar))
        }
    }
}

/// The versions the U1 renders show.
enum AppUpdateSample {
    static let installed = Version(0, 10, 2)
    static let latest = Version(0, 10, 3)

    /// A store over its own throwaway defaults suite holding `state`, enabled, asking `app` for the CLI.
    @MainActor static func store(_ state: UpdateState, app: AppStore) -> AppUpdateStore {
        let suite = "skillcask.ui.previews.updates"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        UpdateDefaults(defaults).save(state)
        return AppUpdateStore(
            installed: installed, defaults: UpdateDefaults(defaults), context: { [weak app] in app?.updateContext })
    }
}

/// The website scope (healthy, as on the U1 board) with the available card.
private struct AppUpdateWindowSample: View {
    @State private var stores: Boot.Stores
    @State private var updates: AppUpdateStore

    @MainActor init() {
        let stores = Boot.fixtures(selecting: Boot.websiteScope, selection: nil)
        _stores = State(initialValue: stores)
        _updates = State(
            initialValue: AppUpdateSample.store(
                UpdateState(consent: .declined, latestSeen: AppUpdateSample.latest), app: stores.app))
    }

    var body: some View {
        MainWindow()
            .skillcaskEnvironment(
                app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client,
                updates: updates)
    }
}

#Preview("U1 card, available") {
    AppUpdateCard(card: .available(AppUpdateSample.latest), installed: AppUpdateSample.installed)
        .padding(AppUpdateCard.padding)
        .frame(width: Size.sidebarWidth)
}
