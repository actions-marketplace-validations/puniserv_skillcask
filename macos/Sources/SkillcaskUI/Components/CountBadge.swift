import SkillcaskDomain
import SwiftUI

/// The count badge of the Components board ("Attention badges"): a capsule at least as wide as it is tall, filled
/// with the severity's dot colour, the number in `captionSemibold`. The text is white on every fill but amber,
/// where the board draws `badgeWarningText` ("dark text, 4.6:1 on amber"). A zero count draws nothing and
/// reserves no space. The sidebar shows up to two through `ScopeBadge`; the toolbar's "Update All" shows one.
public struct CountBadge: View {
    /// The two board sizes: the sidebar and toolbar badge (`Size.badge`, 18) and the chip-count variant
    /// (`Size.badgeSmall`, 16). Both set the type at the 11 pt caption: the board's 10 pt on the small one is
    /// below the floor.
    public enum Variant: Hashable, Sendable {
        case regular
        case small

        /// Capsule height; also the minimum width, so a one-digit badge is a circle.
        public var height: CGFloat {
            switch self {
            case .regular: Size.badge
            case .small: Size.badgeSmall
            }
        }

        /// The board's `min-width` equals its `height` for both sizes.
        public var minWidth: CGFloat { height }
    }

    public let count: Int
    public let severity: Severity
    public let variant: Variant

    public init(_ count: Int, severity: Severity, variant: Variant = .regular) {
        self.count = count
        self.severity = severity
        self.variant = variant
    }

    /// The badge text: `nil` for zero or less (nothing is drawn), otherwise the number in the user's locale.
    nonisolated public static func text(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count.formatted()
    }

    /// What VoiceOver reads: the blue badge counts updates, red and amber count rows needing attention, and a
    /// neutral or ok badge (chip counts) reads its number, the chip's title giving the context.
    nonisolated public static func accessibilityLabel(count: Int, severity: Severity) -> String {
        switch severity {
        case .update: Labels.badgeUpdates(count)
        case .error, .warning: Labels.badgeAttention(count)
        case .ok, .neutral: count.formatted()
        }
    }

    /// The number's colour on the fill: the board's `#fff` (`--sel-text`, gap G5) on every fill but amber, which
    /// takes the `badgeWarningText` token for contrast.
    nonisolated static func textColor(_ severity: Severity) -> Color {
        severity == .warning ? .badgeWarningText : .white
    }

    public var body: some View {
        if let text = Self.text(count) {
            Text(text)
                .font(Font.Token.captionSemibold)
                .foregroundStyle(Self.textColor(severity))
                .lineLimit(1)
                .padding(.horizontal, Spacing.xs)
                .frame(minWidth: variant.minWidth)
                .frame(height: variant.height)
                .background(Color.statusDot(severity), in: Capsule())
                .accessibilityLabel(Self.accessibilityLabel(count: count, severity: severity))
        }
    }
}

#Preview("CountBadge, light") {
    HStack(spacing: Spacing.s) {
        CountBadge(3, severity: .error)
        CountBadge(12, severity: .warning)
        CountBadge(2, severity: .update)
        CountBadge(1, severity: .ok)
        CountBadge(5, severity: .neutral, variant: .small)
        CountBadge(123, severity: .error)
        CountBadge(0, severity: .error)
    }
    .padding(Spacing.l)
    .background(Color.surfaceSidebar)
}

#Preview("CountBadge, dark") {
    HStack(spacing: Spacing.s) {
        CountBadge(3, severity: .error)
        CountBadge(12, severity: .warning)
        CountBadge(2, severity: .update)
        CountBadge(1, severity: .ok)
        CountBadge(5, severity: .neutral, variant: .small)
        CountBadge(123, severity: .error)
        CountBadge(0, severity: .error)
    }
    .padding(Spacing.l)
    .background(Color.surfaceSidebar)
    .preferredColorScheme(.dark)
}
