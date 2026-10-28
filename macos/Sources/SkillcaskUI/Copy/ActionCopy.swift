/// The words of the toolbar and Overview runs (S11, Activity board): the present-progressive title in the list
/// header while a run is in flight, the toast line when it ends. Views and `ActionRunner` never spell these.
public enum ActionCopy {
    // MARK: - Titles (List-States "Checking…", S11 "short runs show an indeterminate bar + title")

    public static let syncing = "Syncing…"
    public static let checking = "Checking…"
    public static let repairing = "Repairing…"
    public static let settingUp = "Setting up…"
    /// Reinstall from lock (`install --frozen`), Security tab. Invented: no board draws the run.
    public static let restoring = "Restoring from the lock…"
    /// The transcript line of a command that could not be built, where the Activity drawer shows the command.
    public static let unbuilt = "(not run)"

    // MARK: - Outcomes (Activity board: "Checked api")

    /// `Synced api`.
    public static func synced(_ scope: String) -> String {
        "Synced \(scope)"
    }

    /// `Checked api`.
    public static func checked(_ scope: String) -> String {
        "Checked \(scope)"
    }

    /// `Repaired api`.
    public static func repaired(_ scope: String) -> String {
        "Repaired \(scope)"
    }

    /// `Restored api from the lock`. Invented.
    public static func restored(_ scope: String) -> String {
        "Restored \(scope) from the lock"
    }

    /// `Set up api`.
    public static func setUp(_ scope: String) -> String {
        "Set up \(scope)"
    }
}
