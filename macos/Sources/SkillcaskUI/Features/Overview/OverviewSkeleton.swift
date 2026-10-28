import SwiftUI

/// The six cards of Overview-States Loading: a skeleton bar for each title and still bars for the body, in the
/// card frame `CardContainer` draws. Nothing reads as "ok" before the CLI says so.
struct OverviewSkeleton: View {
    /// The board's title bar widths and body line fractions, card by card.
    static let cards: [(title: CGFloat, lines: [CGFloat])] = [
        (90, [0.85, 0.6]), (70, [0.7, 0.5]), (110, [0.8]), (60, [0.9, 0.9, 0.4]), (50, [0.75, 0.65]), (60, [0.55]),
    ]

    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: ScopeOverviewView.gridGap) {
            ForEach(Array(Self.cards.enumerated()), id: \.offset) { _, card in
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SkeletonBar(width: card.title)
                    SkeletonLines(fractions: card.lines, spacing: Spacing.inline)
                }
                .padding(.vertical, Size.cardPaddingV)
                .padding(.horizontal, Size.cardPaddingH)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Color.separator, lineWidth: Size.hairline))
            }
        }
        .accessibilityHidden(true)
    }
}
