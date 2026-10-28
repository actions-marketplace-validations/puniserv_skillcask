import Foundation

/// The words of the skill detail header (Main and Detail-States boards): tab titles, the action buttons, the
/// quiet texts that stand in for a button, and the update strip. Views never spell these themselves.
public enum DetailCopy {
    // MARK: - Tabs

    /// The title of a detail section: always the plain word, never with a count (Q9: the board's "Versions 1"
    /// badge has no place in a system segmented control; see `DetailTabs`).
    public static func tab(_ tab: DetailTab) -> String {
        switch tab {
        case .overview: "Overview"
        case .contents: "Contents"
        case .security: "Security"
        case .versions: "Versions"
        }
    }

    /// The accessibility label of the segmented control (the board's `aria-label`).
    public static let sections = "Detail sections"

    // MARK: - State line

    /// The header's state line of a row with an update; the versions sit in the title row and on the button.
    public static let updateAvailable = "Update available"

    /// The third line of a not managed skill whose source nothing recorded (Detail-States).
    public static let noPackageRecorded = "No package recorded"

    // MARK: - Actions

    /// `Update to 1.4.0…`, the primary button when a newer version sits inside the range.
    public static func update(to version: String) -> String {
        "Update to \(version)…"
    }

    /// The primary button of a not managed skill.
    public static let adopt = "Adopt…"

    /// The text in the button's place when the lock is current.
    public static let upToDate = "Up to date"

    /// The text in the button's place when `outdated` has not answered (offline).
    public static let updatesUnknown = "Updates unknown"

    /// The note in the actions' place of a project skill.
    public static let editInRepository = "Edit it in the repository"

    /// The trailing destructive button.
    public static let remove = "Remove…"

    // MARK: - Update strip

    /// `1.4.0 is available`, the bold start of the strip sentence.
    public static func available(_ version: String) -> String {
        "\(version) is available"
    }

    /// The rest of the strip sentence; the board also quotes the range (`^1.2`), which no CLI document prints.
    public static let insideRange = "inside your allowed range."

    /// `Released 24 Oct 2026, 3 days ago.`
    public static func released(_ date: Date, now: Date) -> String {
        "Released \(Formatters.dayMonthYear(date)), \(Formatters.daysAgo(date, now: now))."
    }

    /// The strip's link to the Review Update sheet.
    public static let reviewChanges = "Review changes…"
}
