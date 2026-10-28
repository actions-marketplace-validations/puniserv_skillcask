/// The words of the toolbar and Overview runs (S11, Activity board): the present-progressive title in the list
/// header while a run is in flight, the toast line when it ends. Views and `ActionRunner` never spell these.
public enum ActionCopy {
    // MARK: - Titles (List-States "Checking…", S11 "short runs show an indeterminate bar + title")

    /// Running board ("Short run") and Flow-F5.
    public static let syncing = "Syncing with skills.lock…"
    /// Sync where skills.toml and skills.lock disagree: `install` resolves and rewrites the lock first. Invented.
    public static let resolving = "Resolving skills.toml and installing…"
    public static let checking = "Checking…"
    /// Flow-F5 ("Repairing links…" in the list header).
    public static let repairing = "Repairing links…"
    public static let settingUp = "Setting up…"
    /// Reinstall from lock (`install --frozen`), Security tab. Invented: no board draws the run.
    public static let restoring = "Restoring from the lock…"
    /// The transcript line of a command that could not be built, where the Activity drawer shows the command.
    public static let unbuilt = "(not run)"

    // MARK: - Failure titles (Running board: "Couldn’t sync sql-review.")

    /// `Couldn’t sync.`: the banner title of a failed Sync (the scope is the window's own).
    public static let couldNotSync = OutcomeCopy.couldNot("sync")
    /// `Couldn’t check.`
    public static let couldNotCheck = OutcomeCopy.couldNot("check")
    /// `Couldn’t repair.`
    public static let couldNotRepair = OutcomeCopy.couldNot("repair")
    /// `Couldn’t set up.`
    public static let couldNotSetUp = OutcomeCopy.couldNot("set up")
    /// `Couldn’t restore from the lock.` Invented, as `restoring`.
    public static let couldNotRestore = OutcomeCopy.couldNot("restore from the lock")

    // MARK: - Outcomes (Activity board: "Checked api")

    /// `Synced api`.
    public static func synced(_ scope: String) -> String {
        "Synced \(scope)"
    }

    /// `Synced api · 1 skill installed`, `Synced api · 3 skills installed` (Flow-F5), from the CLI's `installed`
    /// lines; `Synced api` when it installed nothing.
    public static func synced(_ scope: String, installed: Int) -> String {
        switch installed {
        case 0: synced(scope)
        case 1: "Synced \(scope) · 1 skill installed"
        default: "Synced \(scope) · \(installed) skills installed"
        }
    }

    /// Sync that resolved skills.toml first: `Resolved api · skills.lock updated`, `Resolved api · skills.lock
    /// updated, 2 skills installed`. Invented, in the voice of `synced(_:installed:)`.
    public static func resolved(_ scope: String, installed: Int) -> String {
        switch installed {
        case 0: "Resolved \(scope) · skills.lock updated"
        case 1: "Resolved \(scope) · skills.lock updated, 1 skill installed"
        default: "Resolved \(scope) · skills.lock updated, \(installed) skills installed"
        }
    }

    /// `Checked api`.
    public static func checked(_ scope: String) -> String {
        "Checked \(scope)"
    }

    /// `Repaired api`.
    public static func repaired(_ scope: String) -> String {
        "Repaired \(scope)"
    }

    /// A Repair that left problems (`doctor --fix --json` with `ok: false`): `Repaired 2 in api, 1 problem left`,
    /// `Nothing repaired in api, 3 problems left`. Invented.
    public static func repaired(_ scope: String, fixed: Int, left: Int) -> String {
        let leftText = left == 1 ? "1 problem left" : "\(left) problems left"
        return fixed == 0 ? "Nothing repaired in \(scope), \(leftText)" : "Repaired \(fixed) in \(scope), \(leftText)"
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
