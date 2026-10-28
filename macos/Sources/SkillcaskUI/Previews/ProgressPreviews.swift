import SwiftUI

extension PreviewRegistry {
    /// P2-8: the Loading skeleton (strip and cards as `Overview-States` lays them out), the list-header
    /// progress of a short run over a list-wide column plus the bare bar, and the system spinner.
    static let progress: [Entry] = [
        Entry(id: "P2-8", state: "skeleton", size: CGSize(width: 600, height: 300)) { AnyView(SkeletonPreview()) },
        Entry(id: "P2-8", state: "progress", size: CGSize(width: 420, height: 140)) { AnyView(ProgressPreview()) },
        Entry(id: "P2-8", state: "spinner", size: CGSize(width: 320, height: 100)) { AnyView(SpinnerPreview()) },
    ]
}

/// The Overview Loading state: the header with its "Checking…" strip, then two skeleton cards on the grouped
/// background. Sample text only; the screen task supplies the copy.
private struct SkeletonPreview: View {
    private static let stripBar: CGFloat = 120
    private static let cardTitles: [CGFloat] = [90, 70]
    private static let cardLines: [[CGFloat]] = [[0.85, 0.6], [0.7, 0.5]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("api")
                        .font(Font.Token.title)
                        .tracking(Font.Token.titleTracking)
                        .foregroundStyle(Color.textPrimary)
                    Text("~/work/api")
                        .font(Font.Token.mono)
                        .foregroundStyle(Color.textSecondary)
                }
                HStack(spacing: Spacing.s) {
                    Spinner(label: "Checking this project…")
                    SkeletonBar(width: Self.stripBar)
                }
            }
            .padding(.top, Spacing.l)
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceWindow)
            Divider().overlay(Color.separator)
            HStack(alignment: .top, spacing: Spacing.cardGap) {
                ForEach(Array(Self.cardLines.enumerated()), id: \.offset) { index, lines in
                    card(title: Self.cardTitles[index], lines: lines)
                }
            }
            .padding(.vertical, Spacing.l)
            .padding(.horizontal, Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.surfaceGrouped)
        }
    }

    private func card(title: CGFloat, lines: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SkeletonBar(width: title)
            SkeletonLines(fractions: lines)
        }
        .padding(.vertical, Size.cardPaddingV)
        .padding(.horizontal, Size.cardPaddingH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Radius.l).stroke(Color.separator))
    }
}

/// The list-header progress of a short run over a list-wide column, then the bare bar.
private struct ProgressPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ProgressHeader(title: "Checking…")
                .frame(width: Size.listWidth)
            MiniProgressBar()
                .frame(width: Size.listWidth)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceWindow)
    }
}

/// The spinner alone and with a label.
private struct SpinnerPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Spinner()
            Spinner(label: "Checking this project…")
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceWindow)
    }
}
