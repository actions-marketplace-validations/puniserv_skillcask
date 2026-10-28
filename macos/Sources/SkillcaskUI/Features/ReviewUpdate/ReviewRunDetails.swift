import SwiftUI

/// The Details of a failed update, disclosed in the sheet under its banner (a deviation, declared in
/// `ReviewUpdateCopy`): Activity cannot open over a modal sheet, so the run's command and transcript show here,
/// with Copy for the whole of it (Activity's `copyText`). The run stays in Activity too. Selection is per line, as
/// in Activity (`ActivityRow`): one lazily laid-out `Text` per line, so a drag selects within one line; Copy takes
/// the whole transcript.
struct ReviewRunDetails: View {
    /// The command line(s) first, in mono, then the transcript.
    let lines: [String]
    /// What Copy puts on the pasteboard.
    let copyText: String

    /// Room for about eight transcript lines before the box scrolls, so the diff keeps most of the sheet.
    static let maxHeight: CGFloat = 132

    /// The lines' own height on the transcript's 15 pt pitch (wrapped lines scroll), at most `maxHeight`.
    private var height: CGFloat {
        min(Self.maxHeight, CGFloat(lines.count) * Font.Token.LineHeight.transcript + 2 * Spacing.inline)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.inline) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(Font.Token.monoSmall)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .textSelection(.enabled)
                .padding(.vertical, Spacing.inline)
                .padding(.horizontal, Spacing.s)
            }
            .frame(height: height)
            .background(Color.surfaceWindow, in: RoundedRectangle(cornerRadius: Radius.m))
            .overlay(RoundedRectangle(cornerRadius: Radius.m).strokeBorder(Color.separator, lineWidth: Size.hairline))
            Button(ReviewUpdateCopy.copyTranscript) { ActivityDrawer.copy(copyText) }
                .controlSize(.small)
        }
    }
}
