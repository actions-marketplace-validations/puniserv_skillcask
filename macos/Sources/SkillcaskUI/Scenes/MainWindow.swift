import SkillcaskCore
import SkillcaskDomain
import SwiftUI

/// The one window (Main and Overview boards, Rationale): a `NavigationSplitView` of sidebar, skills list and
/// detail, the unified toolbar, the scope's name and path as the window title. Column widths are the Tokens
/// board's (sidebar 220 / min 180, list 360 / min 300, detail min 400). Those ideals sum to 980 and the detail's
/// 400 is fixed, so at the 960 pt minimum the list gives first (360 → 340) and the sidebar stays at 220; the
/// user can narrow either to its minimum (tokens.md G9 left the choice open; this is what `NavigationSplitView`
/// does with these values). A project without skills.toml shows the Set Up block in the detail and an empty
/// list. The stores come from the environment (`skillcaskEnvironment`); the scene boots the app on appear.
public struct MainWindow: View {
    /// The window's minimum height; the boards are 800 tall, 600 keeps the Overview grid readable.
    public static let minHeight: CGFloat = 600

    @Environment(AppStore.self) private var app
    @Environment(ActionRunner.self) private var runner
    @State private var columns = NavigationSplitViewVisibility.all

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: Size.sidebarMinWidth, ideal: Size.sidebarWidth)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: Size.listMinWidth, ideal: Size.listWidth)
        } detail: {
            detail
                .frame(minWidth: Size.detailMinWidth)
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar { ScopeToolbar(app: app, runner: runner, store: app.selectedStore) }
        .focusedSceneValue(\.appStore, app)
        .focusedSceneValue(\.scopeStore, app.selectedStore)
        .focusedSceneValue(\.actionRunner, runner)
        .frame(minWidth: Size.windowMinWidth, minHeight: Self.minHeight)
        .task { await app.boot() }
    }

    // MARK: - Derived

    private var title: String {
        app.selectedScope.map(ShellCopy.name(of:)) ?? ""
    }

    private var subtitle: String {
        guard let scope = app.selectedScope, let item = app.item(for: scope) else { return "" }
        return item.subtitle ?? ""
    }

    // MARK: - Columns

    @ViewBuilder private var content: some View {
        if let store = app.selectedStore, isSetUp {
            SkillListView(store: store)
        } else {
            Color.surfaceWindow
        }
    }

    @ViewBuilder private var detail: some View {
        if let store = app.selectedStore {
            if isSetUp {
                SkillDetailView(store: store)
            } else {
                notSetUp(store)
            }
        } else {
            unavailable
        }
    }

    /// The selected scope has (or is assumed to have) a skills.toml.
    private var isSetUp: Bool {
        app.selectedScope.flatMap { app.item(for: $0)?.isSetUp } ?? true
    }

    /// Overview-States "Folder without skills.toml": the Scope Overview's Set Up block under the scope's header.
    /// The agents Set Up would link are not known before `init` runs, so the body names none.
    private func notSetUp(_ store: ScopeStore) -> some View {
        ScopeOverviewView(store: store, isSetUp: false)
    }

    /// Until the onboarding sheet (P3-7): the CLI state in the detail column, nothing else.
    @ViewBuilder private var unavailable: some View {
        switch app.cli {
        case .locating:
            Spinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.surfaceGrouped)
        case .missing:
            EmptyState(
                icon: "terminal", tone: .error, title: ErrorCopy.binaryMissingTitle,
                body: ErrorCopy.binaryMissingReason + " " + ErrorCopy.binaryMissingAction
            )
            .background(Color.surfaceGrouped)
        case .tooOld:
            EmptyState(
                icon: "terminal", tone: .error, title: ErrorCopy.tooOldTitle,
                body: ErrorCopy.tooOldReason + " " + ErrorCopy.tooOldAction
            )
            .background(Color.surfaceGrouped)
        case .ready:
            Color.surfaceGrouped
        }
    }
}

#Preview("MainWindow, light") {
    let stores = Boot.fixtures()
    MainWindow()
        .skillcaskEnvironment(app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
        .frame(width: 1280, height: 800)
}

#Preview("MainWindow, dark") {
    let stores = Boot.fixtures(selecting: Boot.apiScope, selection: nil)
    MainWindow()
        .skillcaskEnvironment(app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
        .frame(width: 1280, height: 800)
        .preferredColorScheme(.dark)
}
