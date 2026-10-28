import SkillcaskDomain

/// The words of the Remove alert (S10: Remove board). The board's panels fix the title, the managed sentence (names,
/// agents, "skills.toml and skills.lock will be updated and the files deleted."), the dependency sentence and the
/// buttons; the agents come from the scope's targets and the names are the skills that actually go (`RemovePlan`).
/// The board's not managed panel ("Delete …?", Move to Trash) is not built: the app changes no file of its own
/// (spec D35), so a not managed skill gets an explanation and Reveal in Finder instead.
///
/// Invented (no board draws them): the no-agent form of `unavailable(_:agents:personal:)`, `siblings(_:packages:)`,
/// the plural of `orphans(_:requirers:)`, `kept(_:)`, `unchecked(_:)`, `filesOnly`, `refusal(_:)`,
/// `cannotTitle(_:)`, `ok`, `notManagedTitle(_:)`, `notManagedBody(_:)`, `removing(_:)`, `couldNotRemove(_:)`,
/// `removedToast(_:kept:scope:)`.
public enum RemoveCopy {
    // MARK: - Title and buttons

    /// `Remove pdf from this project?`, `Remove caveman from My Skills?`, `Remove 3 skills from this project?`.
    public static func title(skills: [String], personal: Bool) -> String {
        let what = skills.count == 1 ? skills[0] : "\(skills.count) skills"
        return "Remove \(what) from \(personal ? ShellCopy.personalScope : "this project")?"
    }

    /// The destructive button: `Remove`, or `Remove 2 Skills` when two skills go (Remove board: the dependency
    /// panel counts the dependency that goes along).
    public static func button(count: Int) -> String {
        count <= 1 ? "Remove" : "Remove \(count) Skills"
    }

    /// The title when nothing selected can be removed: `Can’t remove safe-refactor`. Invented.
    public static func cannotTitle(_ skills: [String]) -> String {
        "Can’t remove \(skills.count == 1 ? skills[0] : "\(skills.count) skills")"
    }

    /// The only button of an alert that removes nothing. Invented.
    public static let ok = "OK"

    /// The title for not managed skills: `standup-summary is not managed by Skillcask`. Invented.
    public static func notManagedTitle(_ skills: [String]) -> String {
        skills.count == 1
            ? "\(skills[0]) is not managed by Skillcask" : "\(skills.count) skills are not managed by Skillcask"
    }

    /// Why nothing is removed, with the board's last sentence. Invented around it.
    public static func notManagedBody(_ skills: [String]) -> String {
        let one = skills.count == 1
        return "Skillcask does not manage \(one ? "this skill" : "these skills"), so it has nothing to remove. "
            + "Nothing in skills.toml or skills.lock changes. To delete \(one ? "it" : "them"), reveal "
            + "\(one ? "it" : "them") in Finder and move \(one ? "it" : "them") to the Trash yourself."
    }

    // MARK: - Message

    /// `pdf will no longer be available to Claude Code and Cursor in this project.` (Remove board); personal skills
    /// drop "in this project". Without agents the sentence names no one (invented form).
    public static func unavailable(_ skills: [String], agents: [String], personal: Bool) -> String {
        let place = personal ? "" : " in this project"
        guard !agents.isEmpty else {
            return "\(OutcomeCopy.list(skills)) will be removed\(personal ? "" : " from this project")."
        }
        let names = agents.map(ShellCopy.agentName)
        return "\(OutcomeCopy.list(skills)) will no longer be available to \(OutcomeCopy.list(names))\(place)."
    }

    /// `safe-refactor is only here because caveman requires it and will be removed too.` (Remove board); the
    /// plural is invented.
    public static func orphans(_ skills: [String], requirers: [String]) -> String {
        skills.count == 1
            ? "\(skills[0]) is only here because \(OutcomeCopy.list(requirers)) requires it and will be removed too."
            : "\(OutcomeCopy.list(skills)) are only here because \(OutcomeCopy.list(requirers)) requires them and "
                + "will be removed too."
    }

    /// `test-writer is part of the same package and will be removed too.`; `packages` is how many packages the
    /// skills come from. Invented: `remove` takes packages.
    public static func siblings(_ skills: [String], packages: Int) -> String {
        let what = packages == 1 ? "the same package" : "the same packages"
        return skills.count == 1
            ? "\(skills[0]) is part of \(what) and will be removed too."
            : "\(OutcomeCopy.list(skills)) are part of \(what) and will be removed too."
    }

    /// A package another one still requires: `pdf stays installed because caveman requires it; only its entry in
    /// skills.toml is removed.` Invented (the CLI prints `kept … as a dependency`).
    public static func kept(_ kept: RemovePlan.Kept) -> String {
        let skills = kept.skills.isEmpty ? [kept.package] : kept.skills
        let one = skills.count == 1
        return "\(OutcomeCopy.list(skills)) \(one ? "stays" : "stay") installed because "
            + "\(OutcomeCopy.list(kept.requirers)) \(kept.requirers.count == 1 ? "requires" : "require") "
            + "\(one ? "it" : "them"); only \(one ? "its" : "their") entry in skills.toml is removed."
    }

    /// The hedge when the app has not loaded who requires a package: `If another package requires pdf, it stays
    /// installed as a dependency.` Invented.
    public static func unchecked(_ skills: [String]) -> String {
        skills.count == 1
            ? "If another package requires \(skills[0]), it stays installed as a dependency."
            : "If another package requires any of them, that one stays installed as a dependency."
    }

    /// The two files (Remove board).
    public static let files = "skills.toml and skills.lock will be updated and the files deleted."
    /// The two files when every package stays installed as a dependency. Invented.
    public static let filesOnly = "skills.toml and skills.lock will be updated."

    /// Why a selected skill stays. Invented; the dependency wording follows the CLI's "is a dependency; remove what
    /// requires it".
    public static func refusal(_ refusal: RemovePlan.Refusal) -> String {
        switch refusal {
        case .dependency(let skill, let requirers):
            "\(skill) is a dependency of \(OutcomeCopy.list(requirers)) and stays; remove what requires it instead."
        case .project(let skill):
            "\(skill) is a project skill and stays; edit it in the repository."
        case .handWritten(let skill):
            "\(skill) was written by hand, is not a package, and stays."
        case .notManaged(let skill):
            "\(skill) is not managed by Skillcask and stays."
        }
    }

    // MARK: - Runs

    /// The list header while `remove` runs: `Removing pdf…`, `Removing 3 skills…`. Invented.
    public static func removing(_ skills: [String]) -> String {
        "Removing \(what(skills))…"
    }

    /// The failure banner's title: `Couldn’t remove pdf.`, `Couldn’t remove 3 skills.` Invented.
    public static func couldNotRemove(_ skills: [String]) -> String {
        OutcomeCopy.couldNot("remove \(what(skills))")
    }

    /// The toast: `Removed pdf from api`, `Removed 3 skills from My Skills`, and when the CLI kept packages as
    /// dependencies `Removed pdf from api; kept acme/lint as a dependency` or `Kept acme/lint as a dependency in
    /// api`. Invented.
    public static func removedToast(_ skills: [String], kept: [String], scope: String) -> String {
        let keptText = "\(OutcomeCopy.list(kept)) as \(kept.count == 1 ? "a dependency" : "dependencies")"
        if skills.isEmpty {
            return "Kept \(keptText) in \(scope)"
        }
        let removed = "Removed \(what(skills)) from \(scope)"
        return kept.isEmpty ? removed : "\(removed); kept \(keptText)"
    }

    private static func what(_ skills: [String]) -> String {
        skills.count == 1 ? skills[0] : "\(skills.count) skills"
    }
}
