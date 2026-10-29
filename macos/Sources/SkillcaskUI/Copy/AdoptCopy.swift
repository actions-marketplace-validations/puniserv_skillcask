import Foundation
import SkillcaskDomain

/// The words of the Adopt sheet (S9: Adopt-States board). Board strings are verbatim; the adopted folder is the
/// real `<config>/adopted/` the CLI moves copies to (`Scope.configDirectory`), `~`-abbreviated, where the board
/// writes `~/.config/skillcask/adopted/`.
///
/// Invented (no board draws them): `knownNote`, `projectTitle`, `projectBody`, `problem(_:)`, `runningBatch(count:)`,
/// `adoptingFallback`, `adoptedItem` (no version printed), `back`, `couldNotAdopt(_:)`, `couldNotAdoptBatch(count:)`,
/// `notRun`, `close`, `nothingToAdopt`, `ended(done:of:failed:)`, `summary(done:scope:)`, `adopted(_:version:)`
/// without a version, the singular forms of `batchBody`, `duration(_:)`'s minutes form, and the end of
/// `differs(folder:)` (the board's "Review the diff after adopting" names a review the app cannot open, Q18).
///
/// From the CLI's own lines (`src/ui.rs` `done`, stdout): the toast and a finished batch row read the version from
/// `added <package> = "<constraint>" (<version>)` (`src/commands.rs` `finish_add`, 1542) and "copy kept" from
/// `adopted <path> (moved to <dest>)` (`adopt`, 1021), which the CLI prints only when it moved a folder aside.
public enum AdoptCopy {
    // MARK: - Titles

    /// The Skill menu item and the list header's button that open the batch (Adopt-States "Batch — Adopt All with
    /// Known Sources…"; Flow-F4 "Button in the list header when the Not managed chip is active").
    public static let adoptAllMenu = "Adopt All with Known Sources…"

    /// `Adopt caveman` for one skill, `Adopt 12 skills` for a batch (Adopt-States).
    public static func title(skills: [String]) -> String {
        skills.count == 1 ? "Adopt \(skills[0])" : "Adopt \(skills.count) skills"
    }

    /// The batch in flight: `Adopting 9 skills · 4 of 9` (Adopt-States "Batch progress").
    public static func batchProgress(count: Int, current: Int) -> String {
        "Adopting \(count) skills · \(current) of \(count)"
    }

    /// The batch after it ended without closing: `Adopted 3 of 9 skills; a failure stopped the rest.` or
    /// `Adopted 4 of 9 skills; Cancel stopped the rest.` Invented.
    public static func ended(done: Int, of count: Int, failed: Bool) -> String {
        "Adopted \(done) of \(count) skills; " + (failed ? "a failure stopped the rest." : "Cancel stopped the rest.")
    }

    /// The single sheet's progress title and Activity's title for one run: `Adopting caveman…` (Flow-F4 "S11 in
    /// sheet · progress").
    public static func running(_ skill: String) -> String {
        "Adopting \(skill)…"
    }

    /// The batch's Activity title: `Adopting 9 skills…`. Invented.
    public static func runningBatch(count: Int) -> String {
        "Adopting \(count) skills…"
    }

    // MARK: - Single, known source

    /// The sentence under the title of a known source, with the real adopted folder (Adopt-States); the view
    /// draws `folder` in mono.
    public static func knownBody(skill: String, folder: String) -> String {
        "Skillcask will install \(skill) from this source and keep your current copy in \(folder) so nothing is lost."
    }

    /// The field's label for a recorded source (Adopt-States).
    public static let knownLabel = "Source · recorded by the tool that installed it"
    /// Unlocks the recorded source (Adopt-States).
    public static let change = "Change…"

    /// What adopting writes. Invented: the board's "with the rule “Up to next major” (^4.0) and pins v4.0.1" names a
    /// constraint and a version the app cannot know before `add` resolves them (0.9.4 prints no document).
    public static func knownNote(skill: String) -> String {
        "Adds \(skill) to your \(ShellCopy.personal) skills.toml and pins the version it installs in skills.lock."
    }

    // MARK: - Single, unknown source

    /// The sentence under the title when nothing is recorded (Adopt-States); the view draws `folder` in mono.
    public static func unknownBody(folder: String) -> String {
        "Nothing recorded where this skill came from. Enter the source; your current copy is kept in \(folder)."
    }
    /// The field's label (Adopt-States).
    public static let sourceLabel = "Source"
    /// The field's placeholder: the three accepted shapes (Adopt-States).
    public static let placeholder = "vendor/name · github:owner/repo · git:https://…"
    /// The amber strip: what happens to a differing copy. Adopt-States' first sentence; its "Review the diff after
    /// adopting." has no route in the app (no CLI command compares the kept copy, Q18), so the end says where the
    /// copy is kept to compare by hand: `… and your copy is kept in ~/.config/skillcask/adopted/ to compare.`
    public static func differs(folder: String) -> String {
        "If the source’s content differs from your copy, the source wins and your copy is kept in \(folder) to "
            + "compare."
    }
    /// The quiet line under the strip (Adopt-States).
    public static let keepLocal = "Or keep it as a local skill: it stays usable, without updates or a lock entry."

    /// Why a typed source is refused; nil while the field is empty (the button is simply disabled). Invented.
    public static func problem(_ problem: PackageSpec.Problem) -> String? {
        switch problem {
        case .empty: nil
        case .packageName: "Use vendor/name in lowercase, e.g. acme/commit, optionally with @version."
        case .github: "Use github:owner/repo, optionally with /skill or @version."
        case .gitURL: "Use git: with an https:// address of owner/repo, without credentials."
        }
    }

    // MARK: - Batch

    /// `9 have a recorded source and are selected. 3 need a source first. Current copies are kept in
    /// ~/.config/skillcask/adopted/.` (Adopt-States); the unknown sentence is left out when every source is known.
    public static func batchBody(known: Int, unknown: Int, folder: String) -> String {
        var text =
            known == 1
            ? "1 has a recorded source and is selected. " : "\(known) have a recorded source and are selected. "
        if unknown > 0 {
            text += unknown == 1 ? "1 needs a source first. " : "\(unknown) need a source first. "
        }
        return text + "Current copies are kept in \(folder)."
    }
    /// The middle column of a row without a source (Adopt-States).
    public static let sourceUnknown = "Source unknown"
    /// The trailing link of a row without a source (Adopt-States): narrows the sheet to that skill.
    public static let needsSource = "needs a source"
    /// The footer before the run (Adopt-States).
    public static let runsOneAtATime = "Runs one at a time; a failure stops the rest."
    /// The footer while the batch runs (Adopt-States).
    public static let cancelStopsAfterCurrent = "Cancel stops after the current item; finished items stay adopted."
    /// The primary button: `Adopt` for one skill, `Adopt 9` for the selected rows (Adopt-States).
    public static func adopt(count: Int?) -> String {
        count.map { "Adopt \($0)" } ?? "Adopt"
    }

    /// A finished row when the CLI printed no version (no `added … (<version>)` line).
    public static let adoptedItem = "Adopted"

    /// A finished row (Adopt-States "Adopted v4.0.1 · copy kept", the version as the CLI printed it): `Adopted 4.0.1
    /// · copy kept` when an `adopted …` line moved this skill's folder aside, `Adopted 4.0.1` when none did.
    public static func adoptedItem(version: String?, copyKept: Bool) -> String {
        let adopted = version.map { "Adopted \($0)" } ?? adoptedItem
        return copyKept ? adopted + " · copy kept" : adopted
    }
    /// `… 6 more`: the collapsed rest of the checklist (Adopt-States).
    public static func more(_ count: Int) -> String {
        "… \(count) more"
    }

    /// Leaves a "needs a source" row for the batch checklist. Invented.
    public static let back = "Back"

    /// The failure title of one adopt: `Couldn’t adopt caveman.` Invented.
    public static func couldNotAdopt(_ skill: String) -> String {
        OutcomeCopy.couldNot("adopt \(skill)")
    }

    /// The failure title of a batch that could not start: `Couldn’t adopt 9 skills.` Invented.
    public static func couldNotAdoptBatch(count: Int) -> String {
        OutcomeCopy.couldNot("adopt \(count) skills")
    }

    /// A waiting row (Adopt-States).
    public static let waiting = "Waiting"
    /// A row an earlier failure or Cancel left out. Invented.
    public static let notRun = "Not run"
    /// The running row before the CLI printed a line. Invented.
    public static let adoptingFallback = "Adopting…"
    /// The footer button once a batch ended and the sheet stayed open. Invented.
    public static let close = "Close"

    /// `2.1 s` under a minute (Adopt-States), `1 min 4 s` above. The minutes form is invented.
    public static func duration(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        if seconds < 60 {
            return String(format: "%.1f s", locale: Locale(identifier: "en_US_POSIX"), seconds)
        }
        let whole = Int(seconds.rounded(.down))
        return "\(whole / 60) min \(whole % 60) s"
    }

    /// The batch's elapsed time in the header: `0:21` (Adopt-States).
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    // MARK: - Outcomes

    /// The toast of one adopt (Flow-F4): `Adopted caveman (4.0.1)`, the version from the CLI's `added` line;
    /// `Adopted caveman` when it printed none. Also a batch item's Activity headline.
    public static func adopted(_ skill: String, version: String?) -> String {
        version.map { "Adopted \(skill) (\($0))" } ?? "Adopted \(skill)"
    }

    /// The batch's one toast: `Adopted 9 skills in My Skills`. Invented.
    public static func summary(done: Int, scope: String) -> String {
        done == 1 ? "Adopted 1 skill in \(scope)" : "Adopted \(done) skills in \(scope)"
    }

    /// The sheet when none of the requested skills is still not managed (adopted or gone meanwhile). Invented.
    public static let nothingToAdopt = "Nothing here is waiting to be adopted any more."

    // MARK: - Project scope

    /// The title of the sheet in a project. Invented.
    public static func projectTitle(skills: [String]) -> String {
        title(skills: skills)
    }

    /// Why a project cannot adopt (`src/commands.rs` `adopt`: "--adopt applies only with --global"). Invented.
    public static func projectBody(skills: [String]) -> String {
        let what = skills.count == 1 ? "\(skills[0])’s folder" : "their folders"
        return "Adopting works only in \(ShellCopy.personalScope). In a project, Skillcask does not move a copy "
            + "aside: move \(what) away yourself, then add the package."
    }
}
