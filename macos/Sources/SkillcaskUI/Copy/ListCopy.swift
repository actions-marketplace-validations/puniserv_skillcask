import SkillcaskDomain

/// The words of the skills list's own controls (S2 note, Components board "hover with actions"): the hover
/// controls and their ⋯ menu, the list-header progress, and the "nothing in this filter" title. The empty and
/// no-matches sentences are `EmptyCopy`'s, the offline line `StripCopy`'s. Views never spell these.
public enum ListCopy {
    // MARK: - Hover controls (S2: "Hover: Update… / ⋯ (Remove…, Adopt…, Reveal in Finder)")

    public static let update = ShellCopy.update
    /// The ⋯ button's accessibility label and help (`aria-label="More"` on the board).
    public static let more = "More"
    public static let remove = DetailCopy.remove
    public static let adopt = DetailCopy.adopt
    public static let revealInFinder = ShellCopy.revealInFinder

    /// The title of a ⋯ menu item.
    public static func title(_ item: SkillRowActions.MenuItem) -> String {
        switch item {
        case .remove: remove
        case .adopt: adopt
        case .revealInFinder: revealInFinder
        }
    }

    // MARK: - Header progress (List-States "Checking…")

    /// The list-header title while the scope's own refresh runs.
    public static let checking = ActionCopy.checking

    // MARK: - Filtered, nothing to show

    /// A chip with no rows and no query (`Nothing in Updates`): the no-matches title needs a query to echo, so
    /// an empty filter says where it looked instead.
    // Q12: invented copy, no board state
    public static func nothingIn(_ filter: Filter) -> String {
        "Nothing in \(FilterCopy.title(filter))"
    }
}

extension ListCopy {
    /// The search field's placeholder: `Search 14 skills  ⌘F`, or `Search skills` for an empty scope
    /// (List-States "Empty after Set Up").
    public static func searchPrompt(count: Int) -> String {
        count > 0 ? ShellCopy.searchPlaceholder(count: count) : ShellCopy.searchLabel
    }
}
