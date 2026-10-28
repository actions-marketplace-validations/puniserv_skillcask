import Foundation
import SkillcaskDomain

/// The words of the detail's Security tab (Security and Security-States boards): the fixed one-line
/// explanation of each audit rule, the findings heading, the all-clear and reach-only sentences, the changed-on-disk
/// actions, the reach card's heading and the footnotes. The CLI's own finding message is shown beside a finding,
/// never reworded; everything around it is here.
public enum SecurityCopy {
    // MARK: - Findings

    /// The heading above the finding groups.
    public static let findings = "Findings"

    /// `from the last scan, 4 min ago · scans run locally on the files in this folder` (Security board).
    public static func findingsSource(checkedAt date: Date, now: Date = .now) -> String {
        "from the last scan, \(DetailOverviewCopy.checkedAgo(date, now: now)) · scans run locally on the files in "
            + "this folder"
    }

    /// The bold title of a rule's group.
    public static func title(_ kind: FindingKind) -> String {
        switch kind {
        case .modified: "Changed on disk"
        case .riskyPattern: "Risky pattern"
        case .invisibleCharacter: "Invisible character"
        case .other(let rule): humanised(rule)
        }
    }

    /// The fixed explanation of a rule, the same for every finding of it: the boards' sentences without the
    /// finding-specific middle ("it downloads a script…", "a right-to-left override ‹U+202E›…"), which comes from
    /// the CLI message on the finding's own line. `.other` is invented: the app cannot explain a rule it does not
    /// know.
    public static func explanation(_ kind: FindingKind) -> String {
        switch kind {
        case .modified:
            "The files differ from the version in the lock. Either someone edited the skill after it was installed, "
                + "or the install was altered."
        case .riskyPattern:
            "The text asks an agent to run something dangerous."
        case .invisibleCharacter:
            "Text an agent sees but you do not. It can hide instructions or reverse what you read."
        case .other:
            "A rule this version of the app does not know yet; the command-line tool’s message is below."
        }
    }

    /// `SKILL.md:12`: a finding's file, relative to the skill's folder, and its line when it has one.
    public static func location(file: String, line: Int?) -> String {
        guard let line else { return file }
        return "\(file):\(line)"
    }

    /// The separator between a finding's location and its message (`SKILL.md:12 · downloads code into a shell`).
    public static let separator = " · "

    /// The finding's button that opens the Contents tab at its line.
    public static let showInFile = "Show in file"

    /// `risky-pattern` → `Risky pattern`: an unknown rule's name as a title.
    static func humanised(_ rule: String) -> String {
        let words = rule.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    // MARK: - Changed on disk, not installed

    // The board's "Review changes…" is not offered: no CLI command diffs the folder against the lock (`diff`
    // compares the lock with what `update` would lock).

    /// The bold title of a `modified` group whose CLI message is `not installed`. Invented: no board draws it.
    public static let notInstalledTitle = "Not installed"
    /// Its fixed explanation. Invented. Says "not installed" rather than "not on disk": audit reports the same
    /// message when the store path is there but is not a folder or cannot be read.
    public static let notInstalledExplanation = "skills.lock pins this skill, but it is not installed here."

    /// The restore button: runs `install --frozen`, which puts back the locked files (Security-States).
    public static func restoreButton(_ reason: LockRestore.Reason) -> String {
        switch reason {
        case .changed: "Reinstall from lock"
        case .notInstalled: "Install from lock"
        }
    }

    /// The warning under the button for edited files, and the confirmation's when any restored skill is edited.
    // Q15: the board claims a backup copy; install keeps none (src/commands.rs place())
    public static let reinstallNote =
        "Reinstalling replaces the edited files with the locked version. Your changes are not kept; copy them first "
        + "if you need them."
    /// The confirmation's message when every restored skill is only missing. Invented.
    public static let installNote = "Installs the version skills.lock pins."

    /// The confirmation's title, naming the skill or the count: `Reinstall jira-syntax from the lock?`,
    /// `Reinstall 2 skills from the lock?`, `Install sql-review from the lock?` (all missing). Invented.
    public static func restoreQuestion(_ restores: [LockRestore]) -> String {
        let verb = restoreConfirm(restores)
        if restores.count == 1, let only = restores.first {
            return "\(verb) \(only.skill) from the lock?"
        }
        return "\(verb) \(restores.count) skills from the lock?"
    }

    /// The confirmation's message: with more than one skill, every name by what happens to it (the run is
    /// scope-wide), then the warning when edits are lost. Invented.
    public static func restoreMessage(_ restores: [LockRestore]) -> String {
        let changed = restores.filter { $0.reason == .changed }.map(\.skill)
        let missing = restores.filter { $0.reason == .notInstalled }.map(\.skill)
        var parts: [String] = []
        if restores.count > 1 {
            var names = ["The command-line tool restores every skill that differs from the lock, not only this one."]
            if !changed.isEmpty {
                names.append("Changed on disk: \(changed.joined(separator: ", ")).")
            }
            if !missing.isEmpty {
                names.append("Not installed: \(missing.joined(separator: ", ")).")
            }
            parts.append(names.joined(separator: "\n"))
        }
        parts.append(changed.isEmpty ? installNote : reinstallNote)
        return parts.joined(separator: "\n\n")
    }

    /// The confirmation's destructive button: "Install" when every restored skill is only missing.
    public static func restoreConfirm(_ restores: [LockRestore]) -> String {
        restores.allSatisfy { $0.reason == .notInstalled } ? "Install" : "Reinstall"
    }
    /// The confirmation's cancel button.
    public static let cancel = "Cancel"

    // MARK: - All clear

    /// The bold lead of the all-clear and reach-only callouts.
    public static let noFindings = "No findings."
    /// After `noFindings` when the text mentions nothing either: the whole tab (Security-States "Clean").
    public static let mentionsNothing = "The text mentions no commands, hosts, paths, variables or scripts."
    /// After `noFindings` when the reach card follows (Security-States "Reach only").
    public static let readReachBelow = "Read below what the text can reach."

    // MARK: - Reach

    /// The reach card's heading.
    public static let reachTitle = "This skill’s text mentions"
    /// The quiet words after the heading: reach is information, not a verdict (Security board).
    public static let reachSubtitle = "what an agent following it could reach; not a judgement"

    /// The reach group of each `Reach` list, in board order, with its items; `ChipGroup` hides the empty ones.
    /// Environment variables are shown as `$NAME`, as the boards draw them.
    public static func groups(_ reach: Reach) -> [(group: ReachCopy.Group, items: [String])] {
        [
            (.commands, reach.commands), (.network, reach.network), (.paths, reach.paths),
            (.env, reach.env.map { $0.hasPrefix("$") ? $0 : "$\($0)" }), (.scripts, reach.scripts),
        ]
    }

    // MARK: - Footnotes

    /// Under the findings: where the rules come from (Security board).
    public static let rulesNote =
        "Findings come from the command-line tool’s scan rules: changed on disk, risky pattern, invisible "
        + "character. The app adds no rules of its own."
    /// Under the reach card when there are no findings (Security-States "Reach only").
    public static let mentionNote =
        "A mention is not a finding. It tells you what an agent following this text may run, fetch or read; decide "
        + "whether that fits your project."

    /// `Scanned 4 min ago. The files match the version in skills.lock.` (Security-States "Clean"); a project or
    /// hand-written skill has no locked version, so it gets the first sentence only.
    public static func scanned(_ date: Date, locked: Bool, now: Date = .now) -> String {
        let scanned = "Scanned \(DetailOverviewCopy.checkedAgo(date, now: now))."
        return locked ? scanned + " The files match the version in \(DetailOverviewCopy.lockFile)." : scanned
    }

    // MARK: - Not audited (Q7)

    /// The bold lead of the not-audited strip. Invented: no board draws the state (Q7).
    public static let notAuditedTitle = "Not audited."
    /// A not managed skill on a CLI whose `audit` lists only the skills it manages (0.9.1). Invented (Q7).
    public static let notAuditedNotManaged = "The command-line tool scans only the skills it manages."
    /// Any other row `audit` did not list (the audit failed or has not run). Invented.
    public static let notAuditedOther = "The last scan did not include this skill."
}
