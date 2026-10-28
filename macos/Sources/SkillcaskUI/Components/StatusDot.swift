import SkillcaskDomain
import SwiftUI

/// The 8 pt status dot, "the one custom-drawn element on a row": a disc in the severity's dot colour, or the dashed
/// outline of the "not set up" view mode. Never shown alone; `StatusLabel` pairs it with its words.
public struct StatusDot: View {
    /// How the dot is drawn. `.notSetUp` is a view mode, not a sixth severity: the outline ignores `severity`.
    public enum Style: Hashable, Sendable {
        /// A solid disc in `Color.statusDot(severity)`.
        case filled
        /// A dashed outline with no fill, for a project with no `skills.toml` yet or a status not read yet.
        case notSetUp
    }

    public let severity: Severity
    public let style: Style

    public init(_ severity: Severity, style: Style = .filled) {
        self.severity = severity
        self.style = style
    }

    /// The dashed outline (Components, Overview-States boards).
    public static var notSetUp: StatusDot { StatusDot(.neutral, style: .notSetUp) }

    /// The board's `border: 1.5px dashed` on the not-set-up dot.
    static let dashWidth: CGFloat = 1.5
    /// Dash and gap in points: five short dashes around the 8 pt circle, the closest a stroke gets to CSS `dashed`.
    static let dash: [CGFloat] = [2, 2]

    public var body: some View {
        shape
            .frame(width: Size.statusDot, height: Size.statusDot)
            .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Subviews

    @ViewBuilder private var shape: some View {
        switch style {
        case .filled:
            Circle().fill(Color.statusDot(severity))
        case .notSetUp:
            Circle().strokeBorder(Color.textTertiary, style: StrokeStyle(lineWidth: Self.dashWidth, dash: Self.dash))
        }
    }

    private var accessibilityLabel: String {
        switch style {
        case .filled: Labels.severity(severity)
        case .notSetUp: Labels.notSetUp
        }
    }
}

#Preview("StatusDot, light") {
    HStack(spacing: Spacing.m) {
        ForEach(Severity.allCases, id: \.self) { StatusDot($0) }
        StatusDot.notSetUp
    }
    .padding(Spacing.l)
    .background(Color.surfaceWindow)
}

#Preview("StatusDot, dark") {
    HStack(spacing: Spacing.m) {
        ForEach(Severity.allCases, id: \.self) { StatusDot($0) }
        StatusDot.notSetUp
    }
    .padding(Spacing.l)
    .background(Color.surfaceWindow)
    .preferredColorScheme(.dark)
}
