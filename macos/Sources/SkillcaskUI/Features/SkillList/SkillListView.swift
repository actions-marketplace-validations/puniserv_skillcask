import SkillcaskDomain
import SwiftUI

/// The skills column (Main, List-States and Running boards). The header holds the search field (⌘F through the
/// Edit › Find command), the sort menu and the filter chips, then, inside the same header, the progress of a short
/// run or refresh and the compact offline strip; a hairline closes it. Under it sits the failure banner of the last
/// run, then the body `ListState` picks: the rows (`SkillListRow` in a `List(selection:)` bound to the store's id,
/// SUI-6), "No skills yet" with Add Skill…, or the no-matches echo with Show All and Clear Search. Stale while
/// refreshing fades the whole list to `SkillRow.staleOpacity`, selection kept; offline hides what only `outdated`
/// knows. The success toast of a run rides at the bottom of the column for its 4 s.
struct SkillListView: View {
    let store: ScopeStore
    /// Previews only: the row drawn hovered (a render has no pointer).
    var hoveredRow: SkillEntry.ID?

    @Environment(AppStore.self) private var app
    @Environment(ActionRunner.self) private var runner
    @Environment(\.openSettings) private var openSettings
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var runner = runner
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Color.separator)
                .frame(height: Size.hairline)
            if let message = runner.banner {
                banner(message)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.surfaceWindow)
        // "Show details" opens Activity at the run; the drawer arrives with its own task.
        .toast($runner.toast)
        .focusedSceneValue(\.focusSearch, FocusSearchAction { isSearchFocused = true })
        .task(id: store.scope) { await store.refreshIfStale() }
    }

    // MARK: - Derived

    private var state: ListState {
        .resolve(store: store, running: runner.current)
    }

    private var count: Int {
        store.snapshot?.entries.count ?? 0
    }

    // MARK: - Header

    /// `padding: 12px 12px 8px; gap: 8px`: search and sort, the chips, then the progress or offline line.
    private var header: some View {
        @Bindable var store = store
        let state = state
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                searchField
                sortMenu
            }
            FilterChipBar(counts: state.chipCounts, dimmed: state.dimmedFilters, selection: $store.filter)
            if let title = state.progressTitle {
                ProgressHeader(title: title)
            }
            if state.isOffline {
                MessageStrip(.info, text: StripCopy.offlineHeader, density: .compact)
            }
        }
        .padding(.top, Spacing.m)
        .padding(.horizontal, Spacing.m)
        .padding(.bottom, Spacing.s)
    }

    /// The board's "Sort by" button as a system menu: Name, State (worst first), Source (S2 note).
    private var sortMenu: some View {
        @Bindable var store = store
        return Menu {
            Picker(ShellCopy.sortBy, selection: $store.sort) {
                ForEach(SkillcaskDomain.SortOrder.allCases, id: \.self) { order in
                    Text(ShellCopy.sortTitle(order)).tag(order)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(ShellCopy.sortBy, systemImage: "arrow.up.arrow.down").labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(ShellCopy.sortBy)
        .accessibilityLabel(ShellCopy.sortBy)
    }

    /// The system text field with the board's glyph and placeholder (`Search 14 skills  ⌘F`).
    private var searchField: some View {
        @Bindable var store = store
        return HStack(spacing: Spacing.inline) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
            TextField(ShellCopy.searchLabel, text: $store.query, prompt: Text(ListCopy.searchPrompt(count: count)))
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .accessibilityLabel(ShellCopy.searchLabel)
        }
        .font(Font.Token.body)
        .padding(.horizontal, Spacing.s)
        .frame(height: Size.search)
        .background(Color.controlFill, in: RoundedRectangle(cornerRadius: Radius.m))
        .overlay(RoundedRectangle(cornerRadius: Radius.m).strokeBorder(Color.controlBorder, lineWidth: Size.hairline))
    }

    // MARK: - Body

    @ViewBuilder private var content: some View {
        switch state.content {
        case .loading:
            Color.clear
        case .empty:
            EmptyState(
                icon: "shippingbox", title: EmptyCopy.noSkillsTitle, body: EmptyCopy.noSkillsBody,
                actions: [.primary(EmptyCopy.addSkill) { app.request(.addSkill(query: nil)) }])
        case .noMatches(let noMatches):
            noMatchesState(noMatches)
        case .rows(let rows):
            list(rows)
        }
    }

    /// List-States "Filtered, no matches": the query echoed, Show All and Clear Search, and the link that looks
    /// for the query in the sources (Add Skill).
    private func noMatchesState(_ noMatches: ListState.NoMatches) -> some View {
        var actions: [EmptyState.Action] = []
        if noMatches.showsShowAll {
            actions.append(.secondary(EmptyCopy.showAll) { store.filter = .all })
        }
        if noMatches.showsClearSearch {
            actions.append(.secondary(EmptyCopy.clearSearch) { store.query = "" })
        }
        let title =
            noMatches.query.isEmpty
            ? ListCopy.nothingIn(noMatches.filter) : EmptyCopy.noMatchesTitle(query: noMatches.query)
        let query = noMatches.query
        let link: EmptyState.Action? =
            noMatches.showsClearSearch
            ? .secondary(EmptyCopy.findInSources(query: query)) { app.request(.addSkill(query: query)) } : nil
        return EmptyState(
            icon: nil, title: title,
            body: noMatches.body,
            actions: actions, link: link)
    }

    private func list(_ rows: [SkillEntry]) -> some View {
        @Bindable var store = store
        let isOffline = state.isOffline
        return List(selection: $store.selection) {
            ForEach(rows) { entry in
                SkillListRow(
                    entry: entry, scope: store.scope, isSelected: entry.id == store.selection, isOffline: isOffline,
                    requiredBy: store.requirerSkills(for: entry), hovering: entry.id == hoveredRow
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .opacity(state.isRefreshing ? SkillRow.staleOpacity : 1)
        .onDeleteCommand { removeSelected() }
        // Esc with the list focused returns the detail to the Scope Overview (S3), as Esc in the detail does.
        .onExitCommand { store.clearSelection() }
        .accessibilityLabel(ShellCopy.skillsLabel)
    }

    /// The failure banner at the top of the column (`margin: 8px 8px 0`): Details, Dismiss, and Retry or Open
    /// Settings as the failure allows; an integrity failure is never retried and stays until dismissed.
    private func banner(_ message: UserMessage) -> some View {
        FailureBanner(
            message,
            // Details opens Activity scrolled to the run; the drawer arrives with its own task.
            onDetails: {},
            onDismiss: { runner.dismissBanner() },
            onRetry: { runner.retry() },
            onSignIn: { openSettings() }
        )
        .padding(.horizontal, Spacing.s)
        .padding(.top, Spacing.s)
    }

    // MARK: - Actions

    /// ⌫ in the list: Remove… for a row that can be removed (the Skill menu's rule).
    private func removeSelected() {
        guard let entry = store.selectedEntry, DetailActions.resolve(entry, offline: false).showsRemove else { return }
        app.request(.remove(skills: [entry.id]))
    }
}
