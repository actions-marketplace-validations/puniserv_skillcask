import Foundation

/// What a toast says: one sentence from `OutcomeCopy`, with the skill names the board draws semibold ("Added
/// **jira-syntax** and **jira-communication** (4.2.0)"), and whether the "Show details" link follows. A new `id` is
/// a new toast: it replaces the one showing and restarts the 4 s.
public struct ToastMessage: Identifiable, Hashable, Sendable {
    /// The toast's mark: the green check of a run that did what it said, or the amber warning of one that ended
    /// at exit 0 but did less or other than asked (a Repair that left problems, an update that locked another
    /// version, a remove that kept a modified copy).
    public enum Tone: Hashable, Sendable {
        case success
        case warning
    }

    public let id: UUID
    public let text: String
    /// The parts of `text` drawn in `Font.Token.calloutSemibold` (`pdf` in `Updated pdf to 1.4.0`); each one's
    /// first occurrence after the previous one, nothing for a part that does not occur.
    public let emphasis: [String]
    public let showsDetails: Bool
    public let tone: Tone

    public init(
        id: UUID = UUID(), text: String, emphasis: String? = nil, showsDetails: Bool = true, tone: Tone = .success
    ) {
        self.init(
            id: id, text: text, emphasizing: emphasis.map { [$0] } ?? [], showsDetails: showsDetails, tone: tone)
    }

    /// A toast with several emphasized parts (the skill names of an Add).
    public init(
        id: UUID = UUID(), text: String, emphasizing: [String], showsDetails: Bool = true, tone: Tone = .success
    ) {
        self.id = id
        self.text = text
        emphasis = emphasizing
        self.showsDetails = showsDetails
        self.tone = tone
    }
}
