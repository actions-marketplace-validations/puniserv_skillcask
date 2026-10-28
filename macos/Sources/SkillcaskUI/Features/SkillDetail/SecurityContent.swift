import SkillcaskCore
import SkillcaskDomain

/// What the Security tab shows for one row (Security and Security-States boards, S5 note), as a pure value so the
/// states are testable without a view: the findings grouped by rule, the reach groups that have items, whether
/// the restore action shows and which skills it restores, and which footnote closes the tab and where.
struct SecurityContent: Hashable {
    /// Which board state the tab is in.
    enum State: Hashable {
        /// `audit` did not list the row (Q7: a not managed skill on 0.9.4, or no audit): a strip, nothing else.
        case notAudited(notManaged: Bool)
        /// No findings and no reach: the all-clear sentence is the whole tab (Security-States "Clean").
        case clean
        /// No findings, but the text mentions things (Security-States "Reach only").
        case reachOnly
        /// At least one finding, `modified` included (Security, Security-States "Changed on disk"; a locked skill
        /// without a folder is a `modified` finding too, shown as "Not installed").
        case findings
    }

    /// One finding of a group: its place and the CLI's message.
    struct Finding: Hashable, Identifiable {
        let id: Int
        /// `SKILL.md:12`, relative to the skill's folder.
        let location: String
        let message: String
        /// The SKILL.md line "Show in file" opens the Contents tab at; nil when the finding has no line or is in
        /// another file (the Contents tab shows SKILL.md only).
        let target: Int?
    }

    /// The findings of one rule, with the rule's fixed explanation (`SecurityCopy.explanation`).
    struct Group: Hashable, Identifiable {
        let kind: FindingKind
        /// Empty for `modified`: its one finding names the folder and tells the CLI user to run `install`, which
        /// the group's own button replaces.
        let findings: [Finding]
        /// A `modified` group whose finding is the CLI's `not installed`: the locked skill has no folder, so the
        /// group reads "Not installed" and claims no edits.
        var isNotInstalled = false

        var id: String { title }

        /// The bold title: the rule's, or "Not installed".
        var title: String { isNotInstalled ? SecurityCopy.notInstalledTitle : SecurityCopy.title(kind) }

        /// The fixed explanation: the rule's, or the not-installed one.
        var explanation: String {
            isNotInstalled ? SecurityCopy.notInstalledExplanation : SecurityCopy.explanation(kind)
        }

        /// Red for the folder differing from the lock, amber for a finding about the text.
        var severity: Severity { kind == .modified ? .error : .warning }

        /// The callout symbol, as the boards draw it: a page for the folder, a triangle for a risky line, a
        /// crossed-out eye for an invisible character; a download arrow for a missing folder (no board draws it).
        var symbol: String {
            switch kind {
            case .modified: isNotInstalled ? "arrow.down.circle" : "doc.badge.plus"
            case .riskyPattern, .other: MessageStrip.warningSymbol
            case .invisibleCharacter: MessageStrip.invisibleSymbol
            }
        }
    }

    /// The quiet line at the bottom of the tab.
    enum Footnote: Hashable {
        /// Security-States "Clean": when the scan ran, and for a locked skill that the files match the lock.
        case scanned(locked: Bool)
        /// Security-States "Reach only": a mention is not a finding.
        case mentions
        /// Security board: the rules come from the CLI.
        case rules
    }

    /// The check of the all-clear callout (Security-States "Clean", "Reach only").
    static let allClearSymbol = "checkmark.circle"

    /// The file the Contents tab shows; only its lines can be scrolled to.
    static let contentsFile = "SKILL.md"

    let state: State
    let groups: [Group]
    /// The reach groups with items, in board order; empty groups are left out.
    let reach: [ChipGroup.Model]
    /// Whether a group is about the text (the "Findings" heading shows only then).
    let hasTextFindings: Bool
    let footnote: Footnote?
    /// This row's own restore (its `modified` finding on a locked skill): "Reinstall from lock" or "Install from
    /// lock" shows only then.
    let restore: LockRestore?
    /// Every skill the restore puts back: `install --frozen` is scope-wide, so the confirmation names them all.
    /// This row first, then the snapshot's others in list order; empty when `restore` is nil.
    let restores: [LockRestore]

    /// `snapshot` is the scope's, for the restores of the other skills; nil restores this row alone.
    init(entry: SkillEntry, snapshot: ScopeSnapshot? = nil) {
        let reach = entry.reach.map { reach in
            SecurityCopy.groups(reach)
                .map { ChipGroup.Model(label: ReachCopy.label($0.group), items: $0.items) }
                .filter { !$0.isHidden }
        }
        self.reach = reach ?? []
        let restore = entry.lockRestore
        self.restore = restore
        restores = restore.map { own in [own] + (snapshot?.lockRestores ?? []).filter { $0.skill != own.skill } } ?? []
        groups = Self.groups(entry.findings, folder: entry.path)
        hasTextFindings = groups.contains { $0.kind.isTextFinding }
        if !entry.findings.isEmpty {
            state = .findings
        } else if reach == nil {
            state = .notAudited(notManaged: entry.isNotManaged)
        } else {
            state = self.reach.isEmpty ? .clean : .reachOnly
        }
        switch state {
        case .clean: footnote = .scanned(locked: entry.isLocked)
        case .reachOnly: footnote = .mentions
        case .findings: footnote = hasTextFindings ? .rules : nil
        case .notAudited: footnote = nil
        }
    }

    /// The restore replaces edited files of at least one skill (its confirmation is destructive); when every
    /// restored skill is only missing, no edit is lost.
    var restoreReplacesFiles: Bool {
        restores.contains { $0.reason == .changed }
    }

    /// Whether a group is about the folder differing from the lock (rule `modified`).
    var isChangedOnDisk: Bool {
        groups.contains { $0.kind == .modified }
    }

    /// Whether the footnote sits at the bottom of the tab (the Security board's `margin-top: auto` under the
    /// findings) rather than right under the callout or card (Security-States "Clean", "Reach only": the panel's
    /// 12 pt gap).
    var isFootnotePinned: Bool {
        footnote == .rules
    }

    /// What "Show in file" does to the detail: switch to the Contents tab, scrolled to `line`.
    static func showInFile(_ line: Int) -> (tab: DetailTab, contentsTarget: Int) {
        (.contents, line)
    }

    /// The confirmation in front of the restore: `install` keeps no copy of edited files, so the run starts only
    /// after an explicit yes to a question that was asked.
    struct ReinstallGate: Hashable {
        /// Whether the confirmation is on screen.
        var isAsking = false

        /// The restore button was clicked: ask.
        mutating func request() {
            isAsking = true
        }

        /// The destructive button: true (run `install`) only when the question was asked; closes it either way.
        mutating func confirm() -> Bool {
            defer { isAsking = false }
            return isAsking
        }

        /// Cancel or dismissal: nothing runs.
        mutating func cancel() {
            isAsking = false
        }
    }

    // MARK: - Grouping

    /// One group per rule, in the order the board's footnote names them (changed on disk, risky pattern,
    /// invisible character), unknown rules last by name; findings keep the CLI's order within a group.
    static func groups(_ findings: [AuditDocument.Finding], folder: String?) -> [Group] {
        var order: [FindingKind] = []
        var byKind: [FindingKind: [Finding]] = [:]
        var notInstalled = false
        for (index, finding) in findings.enumerated() {
            let kind = finding.kind
            if byKind[kind] == nil {
                order.append(kind)
                byKind[kind] = []
            }
            guard kind != .modified else {
                notInstalled = notInstalled || finding.lockRestoreReason == .notInstalled
                continue
            }
            let file = relative(finding.path, to: folder)
            byKind[kind]?
                .append(
                    Finding(
                        id: index, location: SecurityCopy.location(file: file, line: finding.line),
                        message: finding.message, target: file == contentsFile ? finding.line : nil))
        }
        return order.sorted { rank($0) < rank($1) }
            .map { Group(kind: $0, findings: byKind[$0] ?? [], isNotInstalled: $0 == .modified && notInstalled) }
    }

    /// `.skills/my-notes/SKILL.md` in `.skills/my-notes` → `SKILL.md`; a path outside the folder stays whole.
    static func relative(_ path: String, to folder: String?) -> String {
        guard let folder, path.hasPrefix(folder + "/") else { return path }
        return String(path.dropFirst(folder.count + 1))
    }

    /// The board's rule order; unknown rules after the known ones, by name.
    private static func rank(_ kind: FindingKind) -> String {
        switch kind {
        case .modified: "0"
        case .riskyPattern: "1"
        case .invisibleCharacter: "2"
        case .other(let rule): "3" + rule
        }
    }
}
