import SkillcaskDomain
import SwiftUI

/// A status dot with its words (Components board "Status dot + label"): 12 pt medium in the severity's text colour,
/// 6 pt after the dot. The copy of a `Health` comes from `Labels`; the version transition of an update is set in
/// `Font.Token.monoSmall` as the board draws it.
public struct StatusLabel: View {
    /// What the label says and which colour it takes.
    public enum Content: Hashable, Sendable {
        /// The vocabulary label of a `Health`, coloured by its severity.
        case health(Health)
        /// Any text in a severity's colour: `Required by caveman`, `→ 1.4.0`, a doctor line.
        case text(Severity, String)
        /// The dashed dot and secondary text of the not-set-up view mode.
        case notSetUp(String)
    }

    public let content: Content
    public let font: Font
    /// The text colour when a caller overrides the severity's own: a row's quiet "Installed" in `Color.textSecondary`.
    public let textColor: Color?
    /// The gap after the dot; the Overview sidebar pairs them 5 pt apart, everything else `Spacing.inline`.
    public let spacing: CGFloat

    /// The label of `health`; the detail header passes its own weight, the skill row its own colour, everything
    /// else keeps the board's medium in `Color.statusText(severity)`.
    public init(
        _ health: Health, font: Font = Font.Token.calloutMedium, textColor: Color? = nil,
        spacing: CGFloat = Spacing.inline
    ) {
        self.init(content: .health(health), font: font, textColor: textColor, spacing: spacing)
    }

    public init(
        _ severity: Severity, _ text: String, font: Font = Font.Token.calloutMedium, textColor: Color? = nil,
        spacing: CGFloat = Spacing.inline
    ) {
        self.init(content: .text(severity, text), font: font, textColor: textColor, spacing: spacing)
    }

    /// The dashed dot with `Labels.notSetUp` (or the board's `Unknown`) in `Color.textSecondary`.
    public static func notSetUp(
        _ text: String = Labels.notSetUp, font: Font = Font.Token.calloutMedium, spacing: CGFloat = Spacing.inline
    ) -> StatusLabel {
        StatusLabel(content: .notSetUp(text), font: font, textColor: nil, spacing: spacing)
    }

    private init(content: Content, font: Font, textColor: Color?, spacing: CGFloat) {
        self.content = content
        self.font = font
        self.textColor = textColor
        self.spacing = spacing
    }

    public var body: some View {
        HStack(spacing: spacing) {
            dot.accessibilityHidden(true)
            text
        }
        .font(font)
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Subviews

    private var dot: StatusDot {
        switch content {
        case .health(let health): StatusDot(health.severity)
        case .text(let severity, _): StatusDot(severity)
        case .notSetUp: StatusDot.notSetUp
        }
    }

    private var text: Text {
        switch content {
        case .health(.updateAvailable(let from, let to)):
            Text(Labels.update) + Text(verbatim: " ")
                + Text(Labels.versionTransition(from: from, to: to)).font(Font.Token.monoSmall)
        case .health(let health): Text(Labels.health(health))
        case .text(_, let text): Text(text)
        case .notSetUp(let text): Text(text)
        }
    }

    private var color: Color {
        if let textColor {
            return textColor
        }
        switch content {
        case .health(let health): return Color.statusText(health.severity)
        case .text(let severity, _): return Color.statusText(severity)
        case .notSetUp: return Color.textSecondary
        }
    }
}

#Preview("StatusLabel, light") {
    VStack(alignment: .leading, spacing: Spacing.s) {
        StatusLabel(.installed)
        StatusLabel(.updateAvailable(from: "1.2.0", to: "1.4.0"))
        StatusLabel(.notManaged)
        StatusLabel(.changedOnDisk)
        StatusLabel(.neutral, Labels.requiredBy(["caveman"]))
        StatusLabel.notSetUp(Labels.unknown)
    }
    .padding(Spacing.l)
    .background(Color.surfaceWindow)
}

#Preview("StatusLabel, dark") {
    VStack(alignment: .leading, spacing: Spacing.s) {
        StatusLabel(.installed)
        StatusLabel(.updateAvailable(from: "1.2.0", to: "1.4.0"))
        StatusLabel(.notManaged)
        StatusLabel(.changedOnDisk)
        StatusLabel(.neutral, Labels.requiredBy(["caveman"]))
        StatusLabel.notSetUp(Labels.unknown)
    }
    .padding(Spacing.l)
    .background(Color.surfaceWindow)
    .preferredColorScheme(.dark)
}
