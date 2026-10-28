import Foundation
import SkillcaskDomain

/// What the Health results popover shows (S12, Health-States), resolved from the scope's last `doctor --json` or
/// `doctor --fix --json` answer without a view: the header dot and title, the groups in the board's order
/// (repaired, problems, warnings), the passed checks behind their disclosure, the footnote and the two buttons.
struct HealthReport: Hashable {
    /// One group of items under its label.
    struct Group: Hashable {
        enum Kind: Hashable {
            case repaired
            case problems
            case warnings
        }

        let kind: Kind
        let label: String
        let items: [Item]

        /// The symbol and colour each item of the group draws.
        var glyph: (symbol: String, severity: Severity) {
            switch kind {
            case .repaired: ("checkmark.circle", .update)
            case .problems: ("xmark.circle", .error)
            case .warnings: ("exclamationmark.triangle", .warning)
            }
        }
    }

    /// One item: the sentence the Health card uses (a path lead in mono, backtick runs in mono) and, when the
    /// group's label does not already say it, the quiet second line naming what fixes it.
    struct Item: Hashable {
        let line: OverviewCopy.Line
        let hint: String?
    }

    /// The trailing footer button besides Repair.
    enum SecondaryButton: Hashable {
        /// Sync, the primary button, while anything is open.
        case sync
        /// Check Again, bordered, when nothing is open (Health-States "All passed").
        case checkAgain
    }

    let severity: Severity
    let title: String
    let groups: [Group]
    /// The passed checks, worded; behind `passedLabel`, collapsed until the user opens it.
    let passed: [String]
    let passedLabel: String
    let footnote: String
    /// Repair has something to fix; otherwise the button stays, disabled (Health-States).
    let canRepair: Bool
    let secondary: SecondaryButton

    static func resolve(_ doctor: ScopeSnapshot.Doctor) -> HealthReport {
        let problems = doctor.problemItems
        let warnings = doctor.warningItems
        let fixed = doctor.fixedItems
        var groups: [Group] = []
        if !fixed.isEmpty {
            groups.append(
                Group(
                    kind: .repaired, label: RunningCopy.repairedGroup(fixed.count),
                    items: fixed.map { Item(line: OverviewCopy.fixed($0).withoutHint, hint: nil) }))
        }
        if !problems.isEmpty {
            let remedies = problems.map { doctor.remedy(of: $0) }
            // The label names a command only when it fixes every item: one item nothing fixes (a folder skillcask
            // did not create) makes it plain "Problems", and each item then says what to do on its own line.
            let named = remedies.contains(nil) ? [] : Set(remedies.compactMap { $0 })
            let labelSaysIt = named.count == 1
            groups.append(
                Group(
                    kind: .problems, label: RunningCopy.problemsGroup(named, count: problems.count),
                    items: zip(problems, remedies).map { item(for: $0, remedy: $1, hinted: !labelSaysIt) }))
        }
        if !warnings.isEmpty {
            groups.append(
                Group(
                    kind: .warnings, label: RunningCopy.warningsGroup,
                    items: warnings.map { item(for: $0, remedy: doctor.remedy(of: $0), hinted: true) }))
        }
        let open = problems + warnings
        let openRemedies = open.map { doctor.remedy(of: $0) }
        let footnote: String
        if open.isEmpty {
            footnote = RunningCopy.allPassedFootnote
        } else if !fixed.isEmpty, openRemedies.allSatisfy({ $0 == .sync }) {
            footnote = RunningCopy.remainingFootnote(open.count)
        } else {
            footnote = RunningCopy.repairFootnote
        }
        let severity: Severity = !problems.isEmpty ? .error : (!warnings.isEmpty ? .warning : .ok)
        return HealthReport(
            severity: severity, title: RunningCopy.title(problems: problems.count, warnings: warnings.count),
            groups: groups, passed: doctor.passedItems.map(OverviewCopy.passed),
            passedLabel: OverviewCopy.checksPassed(doctor.passed.count), footnote: footnote,
            canRepair: doctor.canRepair, secondary: open.isEmpty ? .checkAgain : .sync)
    }

    private static func item(for item: DoctorItem, remedy: DoctorItem.Remedy?, hinted: Bool) -> Item {
        Item(
            line: OverviewCopy.problem(item).withoutHint,
            hint: hinted ? RunningCopy.remedyHint(item, remedy: remedy) : nil)
    }
}

extension OverviewCopy.Line {
    /// The line without the card's trailing hint: the popover says what fixes an item on its own second line.
    fileprivate var withoutHint: OverviewCopy.Line {
        OverviewCopy.Line(lead: lead, words: words)
    }
}
