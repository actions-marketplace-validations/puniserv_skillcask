import SkillcaskCore
import SkillcaskDomain

/// What the skills column shows (S2 states, List-States board), resolved from the store's values without a view:
/// the rows, "No skills yet" after Set Up, or "Nothing matches" for a query or chip that hides every row; and on
/// top of any of them whether the list is stale while refreshing (rows at 50 %, the header progress) and offline
/// (the compact strip, update badges and "→ x.y.z" hidden, the Updates chip dimmed without a count).
public struct ListState: Hashable, Sendable {
    /// The column's body.
    public enum Content: Hashable, Sendable {
        /// No snapshot yet: the first load (the detail column explains a failure).
        case loading
        /// skills.toml exists and lists no skill (List-States "Empty after Set Up").
        case empty
        /// Rows exist but the chip and the query hide all of them (List-States "Filtered, no matches").
        case noMatches(NoMatches)
        /// The visible rows, in the sort order.
        case rows([SkillEntry])
    }

    /// The echo of a search that found nothing: the query, the chip, and how many rows match in All.
    public struct NoMatches: Hashable, Sendable {
        public let query: String
        public let filter: Filter
        public let matchesInAll: Int

        /// "Show All" offered when a chip narrows the rows.
        public var showsShowAll: Bool { filter != .all }
        /// "Clear Search" and the "Find … in sources" link offered when there is a query.
        public var showsClearSearch: Bool { !query.isEmpty }
        /// The body under the title (`in Updates. 1 skill matches in All.`): only when a query is echoed; an empty
        /// chip without a query shows its title (`ListCopy.nothingIn`) and Show All alone (Q12).
        public var body: String? {
            query.isEmpty ? nil : EmptyCopy.noMatchesBody(filter: filter, matchesInAll: matchesInAll)
        }
    }

    public let content: Content
    public let isRefreshing: Bool
    public let isOffline: Bool
    /// The header progress title: the running action's, else "Checking…" while refreshing; nil hides the bar.
    public let progressTitle: String?
    /// The chip badges; offline, Updates has none (`outdated` has not answered).
    public let chipCounts: [Filter: Int]

    /// Chips drawn at 50 %: Updates while offline.
    public var dimmedFilters: Set<Filter> { isOffline ? [.updates] : [] }

    /// The rows, or none for the other contents.
    public var rows: [SkillEntry] {
        if case .rows(let rows) = content { rows } else { [] }
    }

    /// The pure rule.
    /// - Parameters:
    ///   - runningTitle: The title of a toolbar run in this scope, if one is in flight.
    public static func resolve(
        snapshot: ScopeSnapshot?, filter: Filter, query: String, sort: SkillcaskDomain.SortOrder, isOffline: Bool,
        isRefreshing: Bool, runningTitle: String? = nil
    ) -> ListState {
        let entries = snapshot?.entries ?? []
        let content: Content
        if snapshot == nil {
            content = .loading
        } else if entries.isEmpty {
            content = .empty
        } else {
            let visible = filter.apply(entries, query: query, sort: sort)
            if visible.isEmpty {
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                content = .noMatches(
                    NoMatches(
                        query: trimmed, filter: filter, matchesInAll: Filter.all.apply(entries, query: trimmed).count))
            } else {
                content = .rows(visible)
            }
        }
        var counts = FilterChipBar.counts(for: snapshot?.attention ?? Attention())
        if isOffline {
            counts[.updates] = nil
        }
        return ListState(
            content: content, isRefreshing: isRefreshing, isOffline: isOffline,
            progressTitle: runningTitle ?? (isRefreshing ? ListCopy.checking : nil), chipCounts: counts)
    }

    /// The state of `store`, with the runner's action when it runs in the store's scope.
    @MainActor public static func resolve(store: ScopeStore, running: ActionRunner.RunningAction?) -> ListState {
        resolve(
            snapshot: store.snapshot, filter: store.filter, query: store.query, sort: store.sort,
            isOffline: store.isOffline, isRefreshing: store.isRefreshing,
            runningTitle: running.flatMap { $0.scope == store.scope ? $0.title : nil })
    }
}
