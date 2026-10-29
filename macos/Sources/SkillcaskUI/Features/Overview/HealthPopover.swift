import SkillcaskDomain
import SwiftUI

/// The Health results popover (S12, Health-States), opened from the Health card's title: the header with the
/// worst severity's dot, `Health · 2 problems, 1 warning` and when doctor answered; then the repaired items in
/// blue, the problems and the warnings, each group under its label; the passed checks as a collapsed disclosure;
/// and the footer with the footnote, Repair (disabled when it has nothing to fix) and Sync, or Check Again when
/// nothing is open. The system popover draws the surface, its border and its shadow.
struct HealthPopover: View {
    let report: HealthReport
    /// `Checked 4 min ago`, `Repaired just now`.
    let when: String
    let isBusy: Bool
    let canSync: Bool
    let onRepair: () -> Void
    let onSync: () -> Void
    let onCheckAgain: () -> Void

    @State private var showsPassed: Bool

    /// The board's `.pop { width: 380px }`.
    nonisolated static let width: CGFloat = 380
    /// The passed checks' indent under the chevron (`padding-left: 22px`): the 14 pt glyph and the 8 pt gap.
    nonisolated static let passedIndent: CGFloat = 22

    /// - Parameter showsPassed: Previews only: draws the passed checks expanded (Health-States "All passed").
    init(
        report: HealthReport, when: String, isBusy: Bool, canSync: Bool, showsPassed: Bool = false,
        onRepair: @escaping () -> Void, onSync: @escaping () -> Void, onCheckAgain: @escaping () -> Void
    ) {
        self.report = report
        self.when = when
        self.isBusy = isBusy
        self.canSync = canSync
        self.onRepair = onRepair
        self.onSync = onSync
        self.onCheckAgain = onCheckAgain
        _showsPassed = State(initialValue: showsPassed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            hairline
            ForEach(Array(report.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    hairline
                }
                groupView(group)
            }
            if !report.passed.isEmpty {
                if !report.groups.isEmpty {
                    hairline
                }
                passed
            }
            hairline
            footer
        }
        .frame(width: Self.width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RunningCopy.popoverLabel)
    }

    // MARK: - Subviews

    private var hairline: some View {
        Rectangle()
            .fill(Color.separator)
            .frame(height: Size.hairline)
    }

    /// `.ph { padding: 10px 14px; gap: 8px; font-weight: 600 }`.
    private var header: some View {
        HStack(spacing: Spacing.s) {
            StatusDot(report.severity)
            Text(report.title)
                .font(Font.Token.bodyEmphasis)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Spacing.s)
            Text(when)
                .font(Font.Token.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, Spacing.cardGap)
        .padding(.horizontal, Size.cardPaddingH)
        .accessibilityElement(children: .combine)
    }

    /// `.grp { padding: 8px 14px; gap: 6px }` with the 11 pt semibold label.
    private func groupView(_ group: HealthReport.Group) -> some View {
        VStack(alignment: .leading, spacing: Spacing.inline) {
            Text(group.label)
                .font(Font.Token.captionSemibold)
                .foregroundStyle(Color.textSecondary)
            ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                itemView(item, glyph: group.glyph)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Size.cardPaddingH)
    }

    /// `.it { gap: 8px; font-size: 12px }`: the glyph, the sentence, and the quiet hint under it.
    private func itemView(_ item: HealthReport.Item, glyph: (symbol: String, severity: Severity)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(Image(systemName: glyph.symbol))
                .font(Font.Token.calloutMedium)
                .foregroundStyle(Color.statusText(glyph.severity))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Size.hairline) {
                sentence(item.line)
                    .font(Font.Token.callout)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = item.hint {
                    Text(hint)
                        .font(Font.Token.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The lead (a path in mono, a name in medium) and the words with their backtick runs in mono, as one text so
    /// a long path wraps with the sentence.
    private func sentence(_ line: OverviewCopy.Line) -> Text {
        let words = EmptyState.bodyText(line.words)
        switch line.lead {
        case .path(let path):
            return Text(verbatim: path).font(Font.Token.monoSmall) + Text(verbatim: " ") + words
        case .name(let name):
            return Text(verbatim: name).font(Font.Token.calloutMedium) + Text(verbatim: " ") + words
        case nil:
            return words
        }
    }

    /// `› 6 checks passed`, collapsed; `⌄ 8 checks passed` and the checks indented under it once opened.
    private var passed: some View {
        VStack(alignment: .leading, spacing: Spacing.inline) {
            Button {
                showsPassed.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text(Image(systemName: showsPassed ? "chevron.down" : "chevron.right"))
                        .font(Font.Token.calloutMedium)
                        .frame(width: Self.passedIndent - Spacing.s, alignment: .leading)
                        .accessibilityHidden(true)
                    Text(report.passedLabel)
                        .font(Font.Token.callout)
                }
                .foregroundStyle(Color.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(OverviewCopy.showPassedHint)
            if showsPassed {
                ForEach(Array(report.passed.enumerated()), id: \.offset) { _, check in
                    Text(check)
                        .font(Font.Token.callout)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Self.passedIndent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Size.cardPaddingH)
    }

    /// `.pf { padding: 10px 14px; background: grouped; font-size: 11px }`: the footnote, Repair, then Sync or
    /// Check Again.
    private var footer: some View {
        HStack(spacing: Spacing.s) {
            Text(report.footnote)
                .font(Font.Token.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Spacing.inline) {
                Button(OverviewCopy.repair, action: onRepair)
                    .buttonStyle(.bordered)
                    .disabled(isBusy || !report.canRepair)
                switch report.secondary {
                case .sync:
                    Button(OverviewCopy.sync, action: onSync)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accent)
                        .disabled(isBusy || !canSync)
                case .checkAgain:
                    Button(RunningCopy.checkAgain, action: onCheckAgain)
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                }
            }
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.vertical, Spacing.cardGap)
        .padding(.horizontal, Size.cardPaddingH)
        .background(Color.surfaceGrouped)
    }
}
