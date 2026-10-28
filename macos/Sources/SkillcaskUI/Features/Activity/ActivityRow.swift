import SkillcaskCore
import SkillcaskDomain
import SwiftUI

/// One run in the Activity drawer (Activity board `.ar`): a chevron, the run in plain words, its exit word in the
/// severity's text colour, duration and start time; `padding: 6px 10px; gap: 8px; font-size: 12px` under a
/// hairline. Expanded (`padding: 0 10px 8px 30px; gap: 4px`): the command and the environment names in SF Mono,
/// the transcript in a `surfaceWindow` box, then Copy and, after a run that may have written it, Reveal
/// skills.lock. The run in flight has a spinner for a chevron, `running`, and its elapsed time, ticking.
/// Selection is per line: the transcript is one lazily laid-out `Text` per line (`ActivityEntry.characterLimit`
/// characters at most), so a drag selects within one line; Copy takes the whole transcript.
struct ActivityRow: View {
    /// Where the expanded block starts: the chevron's column plus the gap (`padding-left: 30px` on the board).
    static let detailInset: CGFloat = Spacing.rowGap + Size.iconInline + Spacing.s

    private enum Run {
        case finished(ActionRunner.ActivityEntry)
        case running(ActionRunner.RunningAction)
    }

    private let run: Run
    private let isFirst: Bool
    private let isExpanded: Bool
    private let onToggle: () -> Void
    private let onCopy: (() -> Void)?
    private let onRevealLock: (() -> Void)?

    init(
        entry: ActionRunner.ActivityEntry, isFirst: Bool, isExpanded: Bool, onToggle: @escaping () -> Void,
        onCopy: @escaping () -> Void, onRevealLock: (() -> Void)?
    ) {
        run = .finished(entry)
        self.isFirst = isFirst
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.onCopy = onCopy
        self.onRevealLock = onRevealLock
    }

    init(running: ActionRunner.RunningAction, isFirst: Bool, isExpanded: Bool, onToggle: @escaping () -> Void) {
        run = .running(running)
        self.isFirst = isFirst
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        onCopy = nil
        onRevealLock = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isFirst {
                Rectangle()
                    .fill(Color.separator)
                    .frame(height: Size.hairline)
            }
            Button(action: onToggle) { summary }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isExpanded ? [.isSelected] : [])
            if isExpanded {
                details
            }
        }
    }

    // MARK: - Summary line

    private var summary: some View {
        // On the first line's baseline, so a title that wraps to two lines keeps chevron, word and time on its
        // first line; the board's body line (18 pt) is the row's minimum, 30 pt with the padding.
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(verbatim: " ")
                .font(Font.Token.calloutMedium)
                .frame(width: Size.iconInline)
                .overlay {
                    leading
                        .frame(width: Size.iconInline, height: Size.iconInline)
                }
            Text(title)
                .font(Font.Token.calloutMedium)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            word
            timing
        }
        .frame(minHeight: Font.Token.Scale.body.lineHeight)
        .padding(.vertical, Spacing.inline)
        .padding(.horizontal, Spacing.rowGap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var leading: some View {
        switch run {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .finished:
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
        }
    }

    private var title: String {
        switch run {
        case .finished(let entry): ActivityCopy.headline(of: entry)
        case .running(let action): action.title
        }
    }

    @ViewBuilder private var word: some View {
        switch run {
        case .finished(let entry):
            Text(ActivityCopy.word(for: entry.ending))
                .font(Font.Token.calloutMedium)
                .foregroundStyle(Color.statusText(ActivityCopy.severity(for: entry.ending)))
                .lineLimit(1)
                .fixedSize()
        case .running:
            Text(ActivityCopy.running)
                .font(Font.Token.calloutMedium)
                .foregroundStyle(Color.textSecondary)
                .fixedSize()
        }
    }

    @ViewBuilder private var timing: some View {
        switch run {
        case .finished(let entry):
            caption(ActivityCopy.timing(entry.duration, startedAt: entry.startedAt))
        case .running(let action):
            TimelineView(.periodic(from: action.startedAt, by: 1)) { context in
                caption(
                    ActivityCopy.elapsed(
                        context.date.timeIntervalSince(action.startedAt), startedAt: action.startedAt))
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Font.Token.caption)
            .foregroundStyle(Color.textSecondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: - Expanded

    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // The commands in SF Mono; the environment line under them is prose naming variables, in SF Pro.
            ForEach(Array(commandLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(index < commandCount ? Font.Token.monoSmall : Font.Token.caption)
                    .foregroundStyle(Color.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            transcript
                .padding(.vertical, Spacing.inline)
                .padding(.horizontal, Spacing.s)
                .background(Color.surfaceWindow, in: RoundedRectangle(cornerRadius: Radius.m))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.m).strokeBorder(Color.separator, lineWidth: Size.hairline))
            if onCopy != nil || onRevealLock != nil {
                HStack(spacing: Spacing.inline) {
                    if let onCopy {
                        Button(ActivityCopy.copy, action: onCopy)
                    }
                    if let onRevealLock {
                        Button(ActivityCopy.revealLock, action: onRevealLock)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.leading, Self.detailInset)
        .padding(.trailing, Spacing.rowGap)
        .padding(.bottom, Spacing.s)
    }

    /// What to add between the wrapped lines of one transcript line so each visual line is 15 pt: the board's
    /// pitch less SwiftUI's own `monoSmall` line (`DiffLineView.naturalLineHeight`, 14), half of it padded above
    /// and below, so a line wrapped n times is exactly 15 × n (as `DiffLineView` does for its 18 pt).
    static let transcriptLineSpacing = max(0, Font.Token.LineHeight.transcript - DiffLineView.naturalLineHeight)

    /// One row per line, laid out lazily (a run keeps up to `ActivityEntry.characterLimit` characters), on the
    /// board's 15 pt pitch (`Font.Token.LineHeight.transcript`), wrapped lines included.
    private var transcript: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(transcriptLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Font.Token.monoSmall)
                    .lineSpacing(Self.transcriptLineSpacing)
                    .padding(.vertical, Self.transcriptLineSpacing / 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Color.textSecondary)
        .textSelection(.enabled)
    }

    private var commandCount: Int {
        switch run {
        case .finished(let entry): ActivityCopy.commands(of: entry).count
        case .running(let action): action.command.isEmpty ? 0 : 1
        }
    }

    private var commandLines: [String] {
        switch run {
        case .finished(let entry): ActivityCopy.commandLines(of: entry)
        case .running(let action): action.command.isEmpty ? [] : [action.command]
        }
    }

    private var transcriptLines: [String] {
        switch run {
        case .finished(let entry): ActivityCopy.transcriptLines(of: entry)
        case .running(let action): ActivityCopy.transcriptLines(action.lines, omitted: action.omittedLines)
        }
    }
}
