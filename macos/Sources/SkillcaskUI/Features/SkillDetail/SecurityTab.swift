import SkillcaskDomain
import SwiftUI

/// The detail's Security tab (S5; Security and Security-States boards) over `SecurityContent`: the findings
/// grouped by rule, each group a tinted callout with the rule's fixed explanation and one line per finding
/// (`SKILL.md:12` in mono, the CLI's message, "Show in file"); the restore action under the `modified` group of a
/// locked skill ("Reinstall from lock", or "Install from lock" when its folder is missing); the reach card of chip
/// groups, framed as information; and a footnote. A clean skill shows the all-clear sentence alone; a row `audit`
/// did not list shows the not-audited strip (Q7).
///
/// Declared deviations: "Show in file" sits on each finding's line, not at the callout's top right, because a
/// group holds every finding of its rule; the board's offending line text (`curl -sL … | sh`) is the CLI's
/// message, since `audit` prints no line text; the changed-on-disk callout lists no files and no counts, and the
/// board's "Review changes…" is left out, because no CLI command diffs the folder against the lock.
struct SecurityTab: View {
    let content: SecurityContent
    let checkedAt: Date?
    /// Disables the restore while any command runs (one run at a time).
    var isBusy = false
    /// Opens the Contents tab scrolled to a SKILL.md line.
    var onShowInFile: (Int) -> Void = { _ in }
    /// Runs `install --frozen`; called only after the confirmation's yes.
    var onReinstall: () -> Void = {}
    var onEmptyClick: () -> Void = {}

    /// The confirmation in front of the restore.
    @State private var reinstallGate = SecurityContent.ReinstallGate()

    /// The Security board's `.grp .l` label column (`width: 160px`).
    static let reachLabelWidth: CGFloat = 160
    /// The board's `gap: 2px` between a callout's lines; off the spacing scale, so named.
    static let lineGap: CGFloat = 2

    var body: some View {
        ViewThatFits(in: .vertical) {
            column
            ScrollView { column }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Color.surfaceWindow
                .contentShape(Rectangle())
                .onTapGesture(perform: onEmptyClick)
        }
    }

    // MARK: - Subviews

    /// Clean and Reach only stack callout, card and footnote at the Security-States panel's 12 pt gap; findings
    /// use the Security board's 16 pt gap with the rules note pushed to the bottom (`margin-top: auto`).
    private var column: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            switch content.state {
            case .notAudited(let notManaged):
                MessageStrip(
                    .neutral, title: SecurityCopy.notAuditedTitle,
                    text: notManaged ? SecurityCopy.notAuditedNotManaged : SecurityCopy.notAuditedOther)
            case .clean:
                VStack(alignment: .leading, spacing: Spacing.m) {
                    allClear(SecurityCopy.mentionsNothing)
                    footnote
                }
            case .reachOnly:
                VStack(alignment: .leading, spacing: Spacing.m) {
                    allClear(SecurityCopy.readReachBelow)
                    reachCard
                    footnote
                }
            case .findings:
                findings
                if !content.reach.isEmpty {
                    reachCard
                }
                if content.isFootnotePinned {
                    Spacer(minLength: 0)
                }
                footnote
            }
        }
        .padding(.horizontal, Size.columnPadding)
        .padding(.vertical, Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func allClear(_ sentence: String) -> some View {
        SecurityCallout(severity: .ok, symbol: SecurityContent.allClearSymbol, alignment: .center) {
            (Text(SecurityCopy.noFindings).font(Font.Token.bodyEmphasis)
                + Text(" " + sentence).font(Font.Token.callout))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var findings: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if content.hasTextFindings {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(SecurityCopy.findings)
                        .font(Font.Token.bodyEmphasis)
                        .foregroundStyle(Color.textPrimary)
                    if let checkedAt {
                        Text(SecurityCopy.findingsSource(checkedAt: checkedAt))
                            .font(Font.Token.callout)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ForEach(content.groups) { group in
                groupCallout(group)
                if group.kind == .modified, let restore = content.restore {
                    restoreActions(restore)
                }
            }
        }
    }

    private func groupCallout(_ group: SecurityContent.Group) -> some View {
        SecurityCallout(severity: group.severity, symbol: group.symbol) {
            VStack(alignment: .leading, spacing: Self.lineGap) {
                Text(group.title)
                    .font(Font.Token.bodyEmphasis)
                Text(group.explanation)
                    .font(Font.Token.callout)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(group.findings) { finding in
                    findingLine(finding)
                }
            }
            .foregroundStyle(Color.textPrimary)
        }
    }

    private func findingLine(_ finding: SecurityContent.Finding) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            (Text(finding.location).font(Font.Token.monoSmall)
                + Text(SecurityCopy.separator + finding.message).font(Font.Token.caption))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let line = finding.target {
                Button(SecurityCopy.showInFile) { onShowInFile(line) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    /// The restore button under the `modified` group, the edit warning when files are replaced, and the
    /// confirmation naming every skill the scope-wide `install --frozen` restores.
    private func restoreActions(_ restore: LockRestore) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Button(SecurityCopy.restoreButton(restore.reason)) { reinstallGate.request() }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            if restore.reason == .changed {
                caption(SecurityCopy.reinstallNote)
            }
        }
        .padding(.top, Spacing.xs)
        .confirmationDialog(
            SecurityCopy.restoreQuestion(content.restores), isPresented: reinstallPresented, titleVisibility: .visible
        ) {
            Button(
                SecurityCopy.restoreConfirm(content.restores), role: content.restoreReplacesFiles ? .destructive : nil
            ) {
                if reinstallGate.confirm() {
                    onReinstall()
                }
            }
            Button(SecurityCopy.cancel, role: .cancel) { reinstallGate.cancel() }
        } message: {
            Text(SecurityCopy.restoreMessage(content.restores))
        }
    }

    /// The reach card: heading, the quiet "not a judgement", then one `ChipGroup` per list with items.
    private var reachCard: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(SecurityCopy.reachTitle)
                    .font(Font.Token.bodyEmphasis)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize()
                Text(SecurityCopy.reachSubtitle)
                    .font(Font.Token.callout)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(content.reach, id: \.label) { group in
                ChipGroup(group, labelWidth: Self.reachLabelWidth)
            }
        }
        .padding(.vertical, Size.cardPaddingV)
        .padding(.horizontal, Size.cardPaddingH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Color.separator, lineWidth: Size.hairline))
    }

    @ViewBuilder private var footnote: some View {
        if let footnote = footnoteText {
            caption(footnote)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Font.Token.caption)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Derived

    /// The dialog's presentation, backed by the gate so a dismissal cancels.
    private var reinstallPresented: Binding<Bool> {
        Binding(
            get: { reinstallGate.isAsking },
            set: { if !$0 { reinstallGate.cancel() } })
    }

    private var footnoteText: String? {
        switch content.footnote {
        case .scanned(let locked): checkedAt.map { SecurityCopy.scanned($0, locked: locked) }
        case .mentions: SecurityCopy.mentionNote
        case .rules: SecurityCopy.rulesNote
        case nil: nil
        }
    }
}
