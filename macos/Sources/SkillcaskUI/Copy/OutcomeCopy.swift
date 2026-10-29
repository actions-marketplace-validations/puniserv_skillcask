/// The words of a run's outcome (Running, Components and AddSkill-States boards): the success toast, and the
/// buttons of a failure banner. Views never spell these themselves.
public enum OutcomeCopy {
    // MARK: - Toast

    /// `Updated pdf to 1.4.0` (Running, Components).
    public static func updated(_ skill: String, to version: String) -> String {
        "Updated \(skill) to \(version)"
    }

    /// `Added jira-syntax and jira-communication (4.2.0)` (AddSkill-States); one, two or more skills.
    public static func added(_ skills: [String], version: String) -> String {
        "Added \(list(skills)) (\(version))"
    }

    /// The toast's link: opens Activity scrolled to the run. The boards use two spellings for the same link:
    /// "Show details" where it sits inline in running text (the toast, AddSkill-States' not-found banner) and
    /// "Details" on a banner's action row (Running, Components). Decision: `showDetails` inline, `details` on
    /// action rows; `FailureBanner` always draws an action row, so it uses `details`.
    public static let showDetails = "Show details"

    // MARK: - Banner

    /// The banner's action-row link to the transcript (Running, Components); see `showDetails`.
    public static let details = "Details"
    public static let dismiss = "Dismiss"
    /// The network banner's button (AddSkill-States, ReviewUpdate-States).
    public static let retry = "Retry"
    /// The sign-in banner's link to the token field (Running).
    public static let openSettings = "Open Settings"
    /// The integrity banner's note beside Details (Running): exit 4 is never retried by the app.
    public static let notRetried = "Not retried automatically"

    /// `Couldn’t sync sql-review.`: a banner title naming what the app was doing.
    public static func couldNot(_ activity: String) -> String {
        "Couldn’t \(activity)."
    }

    // MARK: - Lists

    /// `a`, `a and b`, `a, b and c`: English without a locale, so the toast reads the same on every Mac.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}
