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
    /// The Remove alert built once per request (its plan is computed when asked for, not on every render).
    @State private var pinnedRemoval: (id: UUID, alert: RemoveAlert)?

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
        .sheet(item: presentedSheet) { presentation in
            if let store = app.store(for: presentation.scope) {
                SheetHost(sheet: presentation.sheet, store: store) { app.dismiss(presentation) }
            } else {
                // The pinned scope has no store (the CLI went away): close rather than show an empty sheet.
                Color.surfaceWindow.task { app.dropOrphanedPresentation() }
            }
        }
        .alert(
            removeAlert?.title ?? "", isPresented: removalShown, presenting: removeAlert,
            actions: { alert in alert.actions(onRemove: { alert.confirm(runner: runner) }) },
            message: { alert in alert.message }
        )
        .onChange(of: app.presentation) {
            app.dropOrphanedPresentation()
            pinnedRemoval = removeAlert.flatMap { alert in app.removal.map { ($0.id, alert) } }
        }
        .onChange(of: app.cli) { app.dropOrphanedPresentation() }
        .task { await app.boot() }
    }

    // MARK: - Sheets (`AppStore.Sheet`)

    /// The sheet on screen, pinned to the scope it was asked for; SwiftUI's own close (Esc when allowed) clears
    /// that presentation only.
    private var presentedSheet: Binding<AppStore.Presentation?> {
        Binding(
            get: { app.presentedSheet },
            set: { if $0 == nil, let shown = app.presentedSheet { app.dismiss(shown) } })
    }

    /// The S10 alert of a Remove request, over the scope it was asked for.
    private var removeAlert: RemoveAlert? {
        guard let removal = app.removal, case .remove(let skills) = removal.sheet,
            let store = app.store(for: removal.scope)
        else { return nil }
        if let pinnedRemoval, pinnedRemoval.id == removal.id {
            return pinnedRemoval.alert
        }
        return RemoveAlert(skills: skills, store: store)
    }

    /// Shown while a Remove request with a store is pending (an orphaned one is dropped); any button or Esc
    /// clears it.
    private var removalShown: Binding<Bool> {
        Binding(get: { removeAlert != nil }, set: { if !$0, let shown = app.removal { app.dismiss(shown) } })
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
