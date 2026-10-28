/// The words of the Review Update sheet (S7: ReviewUpdate and ReviewUpdate-States boards).
///
/// Board strings are verbatim. Invented strings (no board draws them), every one declared here:
/// - `loading` "Fetching the changes…"
/// - `updatingAll` "Updating 2 packages…", `updatedAll` "Updated pdf and review-pr"
/// - `upToDateAllTitle` "Everything is up to date", `upToDateAllBody`
/// - `upToDateBody` without a known range ("… Nothing newer exists inside your range.") and without a known
///   version ("pdf matches skills.lock. …")
/// - `fetchFailedAll` "Couldn’t fetch the changes", `fetchFailed` without a version ("… for pdf")
/// - `flagged(_:)` "1 flagged line"; the plurals "2 risky patterns", "2 invisible characters"
///
/// Flags (Q11 interim): a pending update shows none, because `audit` describes only the installed version. The
/// flag words (`flagsCallout`, `nextFlagged`, `flagged`) are the planned capability's, used only once the CLI gives
/// findings of the new version; today only the `flags-planned` preview state draws them.
/// - `elsewhere(_:)` "Update locks 1.3.0, the newest version your range allows; 1.4.0 needs a range change."
/// - `footer` without agents, `footerAll` for three or more packages and its second clause (see `footerAll`)
/// - `findPrevious`, `findNext`, `matches(_:of:)` "2 of 5", `noMatches` "No matches"
/// - `wrapHelp`
/// - `couldNotUpdate(_:)` "Couldn’t update pdf." / "Couldn’t update the packages."
public enum ReviewUpdateCopy {
    // MARK: - Header

    /// `Update pdf`, or `Update pdf 1.2.0 → 1.4.0` once the versions are known (ReviewUpdate board).
    public static func title(package: String, from: String? = nil, to: String? = nil) -> String {
        guard let from, let to else { return "Update \(package)" }
        return "Update \(package) \(from) → \(to)"
    }

    /// `1.2.0 → 1.4.0`, the mono part of the title; `1.4.0` for a package new to the lock.
    public static func versions(from: String?, to: String) -> String {
        guard let from else { return to }
        return "\(from) → \(to)"
    }

    /// Update All before the packages are known; `Update 2 packages` once they are (ReviewUpdate-States).
    public static let updateAllTitle = ShellCopy.updateAll

    /// `Update 2 packages` (ReviewUpdate-States).
    public static func updateAllTitle(count: Int) -> String {
        count == 1 ? "Update 1 package" : "Update \(count) packages"
    }

    /// `anthropics/skills · GitHub · 4 files · +31 −9` (ReviewUpdate board); the source is left out when unknown.
    public static func subtitle(
        package: String, source: String?, files: Int, additions: Int, deletions: Int
    )
        -> String
    {
        ([package, source, self.files(files)] + counts(additions: additions, deletions: deletions))
            .compactMap { $0 }.joined(separator: RowCopy.separator)
    }

    /// `api · pdf, review-pr · 7 files` (ReviewUpdate-States).
    public static func updateAllSubtitle(scope: String, names: [String], files: Int) -> String {
        [scope, names.joined(separator: ", "), self.files(files)].joined(separator: RowCopy.separator)
    }

    /// `4 files`, `1 file`.
    public static func files(_ count: Int) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }

    /// `+31 −9` as one item, nothing when both are zero.
    static func counts(additions: Int, deletions: Int) -> [String?] {
        let text = DiffCopy.counts(additions: additions, deletions: deletions)
        return [text.isEmpty ? nil : text]
    }

    /// The Wrap checkbox (ReviewUpdate board).
    public static let wrap = "Wrap"
    /// Its tooltip. Invented.
    public static let wrapHelp = "Wrap long lines instead of scrolling sideways"
    /// The find field's placeholder (ReviewUpdate board).
    public static let findPlaceholder = "Find in diff"
    /// The find buttons' labels and tooltips. Invented.
    public static let findPrevious = "Previous match"
    public static let findNext = "Next match"
    /// `2 of 5` beside the find field. Invented.
    public static func matches(_ index: Int, of count: Int) -> String {
        "\(index) of \(count)"
    }

    public static let noMatches = "No matches"

    // MARK: - Callouts

    /// The flag callout of the planned capability (findings of the new version), board wording: "The new version
    /// has 1 risky pattern and 1 invisible character; the flagged lines are outlined below." The board's last
    /// sentence ("The tag v1.4.0 has not moved since it was published.") is left out: the CLI can confirm it only
    /// for a GitHub tag.
    public static func flagsCallout(risky: Int, invisible: Int) -> String {
        let parts = [risky > 0 ? riskyPatterns(risky) : nil, invisible > 0 ? invisibleCharacters(invisible) : nil]
            .compactMap { $0 }
        return "The new version has \(OutcomeCopy.list(parts)); the flagged lines are outlined below."
    }

    /// `1 risky pattern`, the bold part of the callout (ReviewUpdate board).
    public static func riskyPatterns(_ count: Int) -> String {
        count == 1 ? "1 risky pattern" : "\(count) risky patterns"
    }

    /// `1 invisible character` (ReviewUpdate board).
    public static func invisibleCharacters(_ count: Int) -> String {
        count == 1 ? "1 invisible character" : "\(count) invisible characters"
    }

    /// The callout's link (ReviewUpdate board).
    public static let nextFlagged = "Next flagged line ↓"

    /// The row offered a version `update` does not reach: `update` takes no version and locks what `diff` shows.
    /// Invented.
    public static func elsewhere(locks: String, offered: String) -> String {
        "Update locks \(locks), the newest version your range allows; \(offered) needs a range change."
    }

    // MARK: - File list

    /// The file list's heading (ReviewUpdate board).
    public static let filesHeading = "Files"
    /// The file list's legend (ReviewUpdate board). The amber-dot clause shows only with findings of the new
    /// version (planned capability), since a pending update has no flags today (Q11 interim).
    public static func legend(withFlags: Bool) -> String {
        withFlags ? "Added · modified · removed. Amber dot = contains a flagged line." : "Added · modified · removed."
    }

    /// `4 files · +31 −9 · 2 flagged lines` under a package in Update All (ReviewUpdate-States); without the flag
    /// count (nil) while no findings of the new version exist, so "no flagged lines" never claims a check.
    public static func sectionSummary(files: Int, additions: Int, deletions: Int, flagged: Int?) -> String {
        ([self.files(files)] + counts(additions: additions, deletions: deletions) + [flagged.map(self.flagged)])
            .compactMap { $0 }.joined(separator: RowCopy.separator)
    }

    /// `2 flagged lines`, `no flagged lines` (ReviewUpdate-States); `1 flagged line` invented.
    public static func flagged(_ count: Int) -> String {
        switch count {
        case 0: "no flagged lines"
        case 1: "1 flagged line"
        default: "\(count) flagged lines"
        }
    }

    /// `jira-syntax and jira-communication are not included: 4.3.0 is still inside the minimum release age.`
    /// (ReviewUpdate-States); `is` for one skill.
    public static func notIncluded(_ skills: [String], version: String?) -> String {
        let verb = skills.count == 1 ? "is" : "are"
        let reason =
            version.map { "\($0) is still inside the minimum release age." }
            ?? "the newer version is still inside the minimum release age."
        return "\(OutcomeCopy.list(skills)) \(verb) not included: \(reason)"
    }

    // MARK: - States

    /// The loading line while `diff` downloads. Invented.
    public static let loading = "Fetching the changes…"

    /// `pdf is up to date` (ReviewUpdate-States).
    public static func upToDateTitle(_ name: String) -> String {
        "\(name) is up to date"
    }

    /// `1.4.0 is installed and matches skills.lock. Nothing newer exists inside your range ^1.2.` (ReviewUpdate-
    /// States); without a range or version the sentence shortens (invented).
    public static func upToDateBody(name: String, version: String?, range: String?) -> String {
        let installed = version.map { "\($0) is installed and matches skills.lock." } ?? "\(name) matches skills.lock."
        let newer =
            range.map { "Nothing newer exists inside your range `\($0)`." }
            ?? "Nothing newer exists inside your range."
        return installed + " " + newer
    }

    /// Update All with nothing in range. Invented.
    public static let upToDateAllTitle = "Everything is up to date"
    public static let upToDateAllBody = "Nothing newer exists inside the ranges in skills.toml."

    /// `Couldn’t fetch the changes for 1.4.0` (ReviewUpdate-States); `for pdf` when no version was offered and
    /// plain for Update All (invented).
    public static func fetchFailed(version: String?, name: String) -> String {
        "Couldn’t fetch the changes for \(version ?? name)"
    }

    public static let fetchFailedAll = "Couldn’t fetch the changes"

    /// `Nothing was changed; pdf 1.2.0 stays installed.` (ReviewUpdate-States), appended to the CLI's sentence.
    public static func nothingChanged(name: String, version: String?) -> String {
        "Nothing was changed; \([name, version].compactMap { $0 }.joined(separator: " ")) stays installed."
    }

    // MARK: - Footer

    /// The primary button (ReviewUpdate board); `Update 2` for Update All (ReviewUpdate-States).
    public static let update = "Update"
    public static func updateAll(_ count: Int) -> String {
        "Update \(count)"
    }

    /// The up-to-date state's button (ReviewUpdate-States).
    public static let done = "Done"

    /// `Updating writes the new version to skills.lock and relinks pdf for Claude Code and Cursor. You can cancel
    /// while it runs.` (ReviewUpdate board); without agents the `for …` part is left out (invented).
    public static func footer(name: String, agents: [String]) -> String {
        let relinks = agents.isEmpty ? "relinks \(name)" : "relinks \(name) for \(OutcomeCopy.list(agents))"
        return "Updating writes the new version to skills.lock and \(relinks). You can cancel while it runs."
    }

    /// Update All's footer. The board's "Both packages are updated in one run; a failure stops before the next
    /// one." does not match the CLI: `update` resolves every package first and writes skills.lock once
    /// (`src/commands.rs` `update`), so a failure while resolving changes nothing. The second clause is invented;
    /// `All 3 packages` is invented too.
    public static func footerAll(count: Int) -> String {
        let subject = count == 2 ? "Both packages are" : count == 1 ? "The package is" : "All \(count) packages are"
        return "\(subject) updated in one run; a failure before skills.lock is written changes nothing."
    }

    // MARK: - Run

    /// `Updating pdf to 1.4.0…` (ReviewUpdate-States progress).
    public static func updating(_ name: String, to version: String) -> String {
        "Updating \(name) to \(version)…"
    }

    /// `Updating 2 packages…`. Invented.
    public static func updatingAll(_ count: Int) -> String {
        count == 1 ? "Updating 1 package…" : "Updating \(count) packages…"
    }

    /// The title of a failed or refused update in the sheet's banner: `Couldn’t update pdf.`, `Couldn’t update the
    /// packages.` Invented, in the voice of the Running board's `Couldn’t sync sql-review.`
    public static func couldNotUpdate(_ name: String?) -> String {
        OutcomeCopy.couldNot("update \(name ?? "the packages")")
    }

    /// `Updated pdf and review-pr`, the toast of Update All. Invented, in the voice of `OutcomeCopy.updated`.
    public static func updatedAll(_ names: [String]) -> String {
        "Updated \(OutcomeCopy.list(names))"
    }
}
