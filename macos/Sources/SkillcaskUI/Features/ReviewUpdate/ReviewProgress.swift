import SwiftUI

/// The update's progress, in place of the diff (ReviewUpdate-States "Progress inside the sheet"): the spinner,
/// `Updating pdf to 1.4.0…` and the elapsed time, the bar, and the CLI's output lines in mono on the grouped
/// surface as they arrive. The bar is the indeterminate `MiniProgressBar` at the board's 4 pt: the CLI reports no
/// progress.
struct ReviewProgress: View {
    let title: String
    /// When the run started; nil before the runner has started it.
    let startedAt: Date?
    let lines: [String]

    /// The block's `padding: 14px 16px` and `gap: 10px`.
    static let paddingV = Spacing.m
    static let paddingH = Spacing.l
    /// The bar's `height: 4px` (ReviewUpdate-States), taller than the list header's 3 pt.
    static let barHeight: CGFloat = 4
    /// The transcript's `padding: 8px 10px`.
    static let transcriptPaddingV = Spacing.s
    static let transcriptPaddingH = Spacing.rowGap

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.rowGap) {
            HStack(spacing: Spacing.rowGap) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(Font.Token.bodyEmphasis)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s)
                if let startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(Self.elapsed(from: startedAt, to: context.date))
                            .font(Font.Token.caption)
                            .foregroundStyle(Color.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
            MiniProgressBar(height: Self.barHeight)
            if !lines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Font.Token.monoSmall)
                                .foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, Self.transcriptPaddingV)
                    .padding(.horizontal, Self.transcriptPaddingH)
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.surfaceGrouped, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Self.paddingV)
        .padding(.horizontal, Self.paddingH)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    /// `0:04`.
    nonisolated static func elapsed(from start: Date, to now: Date) -> String {
        Duration.seconds(max(0, now.timeIntervalSince(start).rounded(.down)))
            .formatted(.time(pattern: .minuteSecond))
    }
}
