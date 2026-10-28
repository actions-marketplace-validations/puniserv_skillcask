import Foundation

/// The few words an Overview card container needs on its own: how a title joins its status ("Health · 2
/// problems") and what VoiceOver says a tappable title does. What a card says (its status, summary and body) is
/// the screen's copy, not the container's.
public enum CardCopy {
    /// The middle dot between a card's title and its status, as every board writes it (`Health · 2 problems`,
    /// `Updates · none`); the same separator a skill row's second line uses.
    public static let separator = RowCopy.separator

    /// `Health · 2 problems`: the title alone when the card has no status.
    public static func title(_ title: String, status: String?) -> String {
        guard let status, !status.isEmpty else { return title }
        return title + separator + status
    }

    /// The accessibility hint of a card title that opens the filtered list ("Every card title links to the
    /// filtered list").
    public static let showsListHint = "Shows the filtered list"
}
