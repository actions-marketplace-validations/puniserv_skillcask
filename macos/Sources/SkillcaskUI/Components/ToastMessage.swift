import Foundation

/// What a toast says: one line from `OutcomeCopy`, with the skill name the board draws semibold, and whether the
/// "Show details" link follows. A new `id` is a new toast: it replaces the one showing and restarts the 4 s.
public struct ToastMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let text: String
    /// The part of `text` drawn in `Font.Token.calloutSemibold` (`pdf` in `Updated pdf to 1.4.0`); the first
    /// occurrence only, nothing when it does not occur.
    public let emphasis: String?
    public let showsDetails: Bool

    public init(id: UUID = UUID(), text: String, emphasis: String? = nil, showsDetails: Bool = true) {
        self.id = id
        self.text = text
        self.emphasis = emphasis
        self.showsDetails = showsDetails
    }
}
