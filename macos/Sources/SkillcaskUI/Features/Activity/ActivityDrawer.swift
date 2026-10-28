import AppKit
import SkillcaskCore
import SwiftUI

/// The Activity drawer (S15, Activity board): a header with the session's run count, Copy All and close, then one
/// row per run this session, newest first, the run in flight on top. A row expands to its command and full
/// transcript with Copy. When Details opened it, it scrolls to that run (`ActionRunner.activityFocus`) and clears
/// the focus. Surface `surfaceGrouped` under a `separatorStrong` top edge, as the board draws it.
struct ActivityDrawer: View {
    @Environment(ActionRunner.self) private var runner
    @Environment(AppStore.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.separatorStrong)
                .frame(height: Size.hairline)
            header
            Rectangle()
                .fill(Color.separator)
                .frame(height: Size.hairline)
            if runner.activity.isEmpty && runner.current == nil {
                Text(ActivityCopy.empty)
                    .font(Font.Token.callout)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                rows
            }
        }
        .background(Color.surfaceGrouped)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ActivityCopy.title)
    }

    // MARK: - Header

    /// `padding: 8px 10px; gap: 8px; font-size: 12px`: the terminal glyph, `Activity`, the run count, Copy All, ×.
    private var header: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "terminal")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Size.iconToolbar, height: Size.iconToolbar)
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
            Text(ActivityCopy.title)
                .font(Font.Token.calloutSemibold)
                .foregroundStyle(Color.textPrimary)
            Text(ActivityCopy.session(runs: runner.sessionRunCount, kept: runner.activity.count))
                .font(Font.Token.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: Spacing.s)
            HStack(spacing: Spacing.xs) {
                Button(ActivityCopy.copyAll) { Self.copy(ActivityCopy.copyAllText(of: runner.activity)) }
                    .disabled(runner.activity.isEmpty)
                Button {
                    runner.toggleActivity()
                } label: {
                    Image(systemName: "xmark")
                }
                .help(ActivityCopy.close)
                .accessibilityLabel(ActivityCopy.close)
            }
            .controlSize(.small)
        }
        // The board's 38 pt: `.btn.sm` (22) inside 8 pt above and below. System small buttons are shorter, so the
        // height is fixed rather than left to the padding.
        .frame(height: Size.buttonSmall + 2 * Spacing.s)
        .padding(.horizontal, Spacing.rowGap)
    }

    // MARK: - Rows

    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let running = runner.current {
                        ActivityRow(
                            running: running, isFirst: true, isExpanded: runner.expandedActivity.contains(running.id),
                            onToggle: { runner.toggleExpanded(running.id) }
                        )
                        .id(running.id)
                    }
                    ForEach(Array(runner.activity.enumerated()), id: \.element.id) { index, entry in
                        ActivityRow(
                            entry: entry, isFirst: index == 0 && runner.current == nil,
                            isExpanded: runner.expandedActivity.contains(entry.id),
                            onToggle: { runner.toggleExpanded(entry.id) },
                            onCopy: { Self.copy(ActivityCopy.copyText(of: entry)) },
                            onRevealLock: entry.mayHaveWrittenLock ? { revealLock(of: entry) } : nil
                        )
                        .id(entry.id)
                    }
                }
            }
            .onChange(of: runner.activityFocus, initial: true) {
                guard let id = runner.activityFocus else { return }
                proxy.scrollTo(id, anchor: .top)
                runner.clearActivityFocus()
            }
        }
    }

    // MARK: - Actions

    /// Selects the scope's skills.lock in Finder, beside the skills.toml `AppStore.manifest(of:)` names.
    private func revealLock(of entry: ActionRunner.ActivityEntry) {
        Workspace.revealManifest(entry.lockFile(beside: app.manifest(of: entry.scope)), root: entry.scope.root)
    }

    /// Puts `text` on the general pasteboard: exactly the text the drawer shows.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
