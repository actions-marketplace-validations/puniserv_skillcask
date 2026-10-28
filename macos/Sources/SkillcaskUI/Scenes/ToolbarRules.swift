import SkillcaskDomain

/// When the toolbar's actions are enabled (designer's note): "Update All … disabled when outdated is empty; Sync
/// enabled only when status says the lock and files disagree". Pure, so the tests pin it over the fixtures.
public enum ToolbarRules {
    /// Overview-States Loading: "Toolbar actions are disabled until the first status result arrives."
    public static func isLoaded(_ snapshot: ScopeSnapshot?) -> Bool {
        snapshot != nil
    }

    /// Add Skill… (toolbar, ⌘N, the empty list's button): the scope has data and no run is in flight (Flow-F2
    /// "Disabled while another command runs in this scope"; one run at a time in the whole app, `ActionRunner.isBusy`).
    public static func canAddSkill(_ snapshot: ScopeSnapshot?, isBusy: Bool) -> Bool {
        isLoaded(snapshot) && !isBusy
    }

    /// The lock and the files disagree: a row is not installed, changed on disk or needs sync.
    public static func canSync(_ snapshot: ScopeSnapshot?) -> Bool {
        (snapshot?.entries ?? [])
            .contains { entry in
                switch entry.health {
                case .notInstalled, .changedOnDisk, .needsSync: true
                default: false
                }
            }
    }

    /// The count on the Update All badge: packages with a newer version inside their range.
    public static func updateAllCount(_ snapshot: ScopeSnapshot?) -> Int {
        snapshot?.availableUpdates.count ?? 0
    }

    /// Update All is enabled when at least one package has such a version.
    public static func canUpdateAll(_ snapshot: ScopeSnapshot?) -> Bool {
        updateAllCount(snapshot) > 0
    }
}
