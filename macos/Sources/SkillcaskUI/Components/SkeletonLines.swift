import SwiftUI

/// A column of `SkeletonBar`s whose widths follow the board's fractions of the container (`85 % / 60 % / 40 %`,
/// repeating), for the card bodies of the `Overview-States` Loading state. The stack has a fixed height so it
/// never claims more room than its lines.
public struct SkeletonLines: View {
    /// The line widths of the first Overview Loading card plus the short closing line of its three-line card.
    public nonisolated static let defaultPattern: [CGFloat] = [0.85, 0.6, 0.4]

    private let fractions: [CGFloat]
    private let spacing: CGFloat
    private let barHeight: CGFloat

    /// - Parameters:
    ///   - count: How many lines; widths come from `SkeletonLines.pattern(count:)`.
    ///   - spacing: Vertical gap between lines.
    ///   - barHeight: Height of every bar.
    public init(count: Int, spacing: CGFloat = Spacing.s, barHeight: CGFloat = SkeletonBar.defaultHeight) {
        self.init(fractions: SkeletonLines.pattern(count: count), spacing: spacing, barHeight: barHeight)
    }

    /// - Parameters:
    ///   - fractions: One width per line as a fraction of the container (`0...1`).
    ///   - spacing: Vertical gap between lines.
    ///   - barHeight: Height of every bar.
    public init(fractions: [CGFloat], spacing: CGFloat = Spacing.s, barHeight: CGFloat = SkeletonBar.defaultHeight) {
        self.fractions = fractions
        self.spacing = spacing
        self.barHeight = barHeight
    }

    /// The first `count` widths of `defaultPattern`, cycling when `count` exceeds it.
    public nonisolated static func pattern(count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        return (0..<count).map { defaultPattern[$0 % defaultPattern.count] }
    }

    /// The height the lines and their gaps need; `0` for no lines.
    public nonisolated static func totalHeight(lines: Int, spacing: CGFloat, barHeight: CGFloat) -> CGFloat {
        guard lines > 0 else { return 0 }
        return CGFloat(lines) * barHeight + CGFloat(lines - 1) * spacing
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(fractions.enumerated()), id: \.offset) { _, fraction in
                    SkeletonBar(width: geometry.size.width * fraction, height: barHeight)
                }
            }
        }
        .frame(height: SkeletonLines.totalHeight(lines: fractions.count, spacing: spacing, barHeight: barHeight))
        .accessibilityHidden(true)
    }
}

#Preview("SkeletonLines, light") {
    SkeletonLines(count: 3)
        .padding(Spacing.l)
        .frame(width: 320)
        .background(Color.surfaceWindow)
}

#Preview("SkeletonLines, dark") {
    SkeletonLines(count: 3)
        .padding(Spacing.l)
        .frame(width: 320)
        .background(Color.surfaceWindow)
        .preferredColorScheme(.dark)
}
