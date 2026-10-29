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
                    let items = Self.items(current: runner.current, activity: runner.activity)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item, isFirst: index == 0)
                            .id(item.id)
                    }
                }
            }
            .onChange(of: runner.activityFocus, initial: true) {
                guard let id = runner.activityFocus else { return }
                proxy.scrollTo(Item.ID.finished(id), anchor: .top)
                runner.clearActivityFocus()
            }
        }
    }

    /// A row of the drawer: the run in flight on top, then the finished runs. The running row's identity never
    /// equals its finished entry's, although both carry the run's UUID: when a run ends, `current` clears and its
    /// entry is inserted in one turn, and a `LazyVStack` that saw one id move from the running row to the entry
    /// kept drawing the stale running cell, its timer ticking, until the drawer was reopened.
    enum Item: Identifiable {
        case running(ActionRunner.RunningAction)
        case finished(ActionRunner.ActivityEntry)

        enum ID: Hashable {
            case running(UUID)
            case finished(UUID)
        }

        var id: ID {
            switch self {
            case .running(let action): .running(action.id)
            case .finished(let entry): .finished(entry.id)
            }
        }
    }

    /// The drawer's rows, newest first.
    static func items(current: ActionRunner.RunningAction?, activity: [ActionRunner.ActivityEntry]) -> [Item] {
        (current.map { [.running($0)] } ?? []) + activity.map { .finished($0) }
    }

    @ViewBuilder private func row(_ item: Item, isFirst: Bool) -> some View {
        switch item {
        case .running(let running):
            ActivityRow(
                running: running, isFirst: isFirst, isExpanded: runner.expandedActivity.contains(running.id),
                onToggle: { runner.toggleExpanded(running.id) })
        case .finished(let entry):
            ActivityRow(
                entry: entry, isFirst: isFirst, isExpanded: runner.expandedActivity.contains(entry.id),
                onToggle: { runner.toggleExpanded(entry.id) },
                onCopy: { Self.copy(ActivityCopy.copyText(of: entry)) },
                onRevealLock: entry.mayHaveWrittenLock ? { revealLock(of: entry) } : nil)
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
