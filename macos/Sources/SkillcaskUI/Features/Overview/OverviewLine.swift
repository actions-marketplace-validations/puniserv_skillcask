import SkillcaskDomain
import SwiftUI

/// One `.line` of an Overview card (`font-size: 12px; gap: 8px`): an optional glyph (a status-coloured symbol or a
/// status dot), the lead (a path in mono or a skill name in medium), the words with their backtick runs in mono,
/// and the quiet hint at the trailing end (`Repair fixes this`). A path keeps its full width and the words wrap
/// instead, as the board does; when the line is too narrow the hint moves under the words.
struct OverviewLine: View {
    /// What sits before the words.
    enum Glyph: Hashable {
        /// An SF Symbol in the severity's text colour (secondary text without one).
        case symbol(String, Severity?)
        case dot(Severity)
    }

    let line: OverviewCopy.Line
    let glyph: Glyph?
    /// The board's `color: var(--text2)` lines (cooldown, outside the range, the passed disclosure).
    let isQuiet: Bool

    init(_ line: OverviewCopy.Line, glyph: Glyph? = nil, isQuiet: Bool = false) {
        self.line = line
        self.glyph = glyph
        self.isQuiet = isQuiet
    }

    init(_ words: String, glyph: Glyph? = nil, isQuiet: Bool = false) {
        self.init(OverviewCopy.Line(words: words), glyph: glyph, isQuiet: isQuiet)
    }

    var body: some View {
        Group {
            if let hint = line.hint {
                // One line when everything fits; otherwise the hint drops under the words, so a long path never
                // squeezes the sentence into broken words.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        glyphView
                        lead
                        wordsText.fixedSize()
                        Spacer(minLength: Spacing.s)
                        hintText(hint)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        glyphView
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                                lead
                                wordsText.fixedSize(horizontal: false, vertical: true)
                            }
                            hintText(hint)
                        }
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    glyphView
                    lead
                    wordsText.fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var wordsText: some View {
        EmptyState.bodyText(line.words)
            .font(Font.Token.callout)
            .foregroundStyle(isQuiet ? Color.textSecondary : Color.textPrimary)
    }

    private func hintText(_ hint: String) -> some View {
        Text(hint)
            .font(Font.Token.caption)
            .foregroundStyle(Color.textSecondary)
            .fixedSize()
    }

    // MARK: - Subviews

    @ViewBuilder private var glyphView: some View {
        switch glyph {
        case .symbol(let name, let severity):
            Text(Image(systemName: name))
                .font(Font.Token.calloutMedium)
                .foregroundStyle(severity.map(Color.statusText) ?? Color.textSecondary)
                .accessibilityHidden(true)
        case .dot(let severity):
            StatusDot(severity)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                .accessibilityHidden(true)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder private var lead: some View {
        switch line.lead {
        case .path(let path):
            Text(path)
                .font(Font.Token.monoSmall)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: true, vertical: false)
        case .name(let name):
            Text(name)
                .font(Font.Token.calloutMedium)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
        case nil:
            EmptyView()
        }
    }
}
