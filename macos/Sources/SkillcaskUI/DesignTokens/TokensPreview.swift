import SkillcaskDomain
import SwiftUI

/// The token sheet: every colour as a flat swatch with its name and both hex values, the type scale, the spacing
/// and radius scales and the fixed sizes, laid out like `design/boards/Tokens.dc.html`. Rendered in both schemes
/// by the `P1-1` registry entry so a reviewer can pick pixels against `docs/handoff/tokens.md`.
public struct TokensPreview: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            header
            HStack(alignment: .top, spacing: Spacing.xxl) {
                Panel(title: "Colour · surfaces, text, controls, brand") { baseColours }
                Panel(title: "Colour · status, pills, selection, diff") { statusColours }
            }
            HStack(alignment: .top, spacing: Spacing.xxl) {
                Panel(title: "Type scale · SF Pro Text, SF Mono") { typeScale }
                VStack(spacing: Spacing.l) {
                    Panel(title: "Spacing") { spacing }
                    Panel(title: "Corner radii") { radii }
                    Panel(title: "Fixed sizes") { sizes }
                }
            }
        }
        .padding(.vertical, Layout.pageInsetV)
        .padding(.horizontal, Layout.pageInsetH)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceWindow)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Skillcask for Mac · design tokens")
                    .font(Font.Token.title)
                    .tracking(Font.Token.titleTracking)
                    .foregroundStyle(Color.textPrimary)
                Text(
                    "\(colorScheme == .dark ? "Dark" : "Light") appearance · hex pairs read light / dark, "
                        + "the active one in text.primary · selection is the system accent, not a token"
                )
                .font(Font.Token.callout)
                .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            RoundedRectangle(cornerRadius: Radius.l)
                .fill(Color.accent)
                .frame(width: Layout.swatch, height: Layout.swatch)
            Text("Skillcask")
                .font(Font.Token.bodyEmphasis)
                .foregroundStyle(Color.textPrimary)
            Text("P1-1")
                .font(Font.Token.mono)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.bottom, Spacing.l)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.separator).frame(height: 1) }
    }

    private var baseColours: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            GroupHeading("Surfaces")
            swatches(.surfaceWindow, .surfaceSidebar, .surfaceGrouped, .surfaceCard, .surfaceHover, .separator)
            swatches(.separatorStrong)
            GroupHeading("Text")
            swatches(.textPrimary, .textSecondary, .textTertiary)
            GroupHeading("Controls and selection")
            swatches(.controlFill, .controlBorder)
            SelectionRow()
            GroupHeading("Brand accent · Iris")
            swatches(.accent, .accentSoft)
        }
    }

    private var statusColours: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            GroupHeading("Status (dot · text · tint)")
            swatches(.statusOkDot, .statusOkText, .statusOkTint)
            swatches(.statusUpdateDot, .statusUpdateText, .statusUpdateTint)
            swatches(.statusWarningDot, .statusWarningText, .statusWarningTint)
            swatches(.statusErrorDot, .statusErrorText, .statusErrorTint)
            swatches(.statusNeutralDot, .statusNeutralText, .statusNeutralTint)
            SeverityStrip()
            GroupHeading("Pill and skeleton")
            swatches(.pillFill, .pillText, .skeleton)
            GroupHeading("Secondary selection and diff")
            swatches(.selectionSoft, .diffAdded, .diffRemoved, .diffRisk, .diffInvisible)
            GroupHeading("Badge text")
            swatches(.badgeWarningText)
        }
    }

    private func swatches(_ tokens: Color.Token...) -> some View {
        ForEach(tokens, id: \.self) { SwatchRow(token: $0) }
    }

    private var typeScale: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Font.Token.Scale.allCases, id: \.self) { scale in
                TypeRow(scale: scale)
                Rectangle().fill(Color.separator).frame(height: 1)
            }
            Text(
                "Monospace is reserved for things the user will meet verbatim in a repository: package names, "
                    + "versions, paths, file names, diff and transcript text. Everything else is SF Pro. "
                    + "Nothing smaller than 11 pt exists; 11 pt is text.secondary or darker. "
                    + "Diff grid line height \(Int(Font.Token.LineHeight.diff)) pt."
            )
            .font(Font.Token.callout)
            .foregroundStyle(Color.textSecondary)
            .padding(.top, Spacing.m)
        }
    }

    private var spacing: some View {
        HStack(alignment: .bottom, spacing: Spacing.m) {
            ForEach(Spacing.catalog.indices, id: \.self) { index in
                let metric = Spacing.catalog[index]
                VStack(spacing: Spacing.xs) {
                    Rectangle().fill(Color.accent).frame(width: metric.value, height: metric.value)
                    Text("\(Int(metric.value))")
                        .font(Font.Token.monoSmall)
                        .foregroundStyle(Color.textPrimary)
                }
            }
            Text(
                "space.1 … space.7 and the card grid gap. Column padding \(Int(Size.columnPadding)), card padding "
                    + "\(Int(Size.cardPaddingV))/\(Int(Size.cardPaddingH)), row height \(Int(Size.row)), sidebar "
                    + "row \(Int(Size.sidebarRow)) (\(Int(Size.sidebarRowSubtitle)) with subtitle), toolbar "
                    + "\(Int(Size.toolbar))."
            )
            .font(Font.Token.callout)
            .foregroundStyle(Color.textSecondary)
            .padding(.leading, Spacing.s)
        }
    }

    private var radii: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.l), count: 3), spacing: Spacing.s) {
            ForEach(Radius.catalog.indices, id: \.self) { index in
                let metric = Radius.catalog[index]
                HStack(spacing: Spacing.s) {
                    RadiusSample(radius: metric.value)
                    Text(metric.value == Radius.pill ? "\(metric.name) capsule" : "\(metric.name) \(Int(metric.value))")
                        .font(Font.Token.monoSmall)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var sizes: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.l), count: 3), spacing: Spacing.xs) {
            ForEach(Size.catalog.indices, id: \.self) { index in
                let metric = Size.catalog[index]
                SizeCell(name: metric.name, value: "\(Int(metric.value))")
            }
            SizeCell(name: "reviewSheet", value: "\(Int(Size.reviewSheet.width)) × \(Int(Size.reviewSheet.height))")
            SizeCell(
                name: "addSkillSheet", value: "\(Int(Size.addSkillSheet.width)) × \(Int(Size.addSkillSheet.height))")
            SizeCell(name: "adoptSheet", value: "\(Int(Size.adoptSheet.width)) × \(Int(Size.adoptSheet.height))")
        }
    }
}

// MARK: - Pieces

/// Sheet geometry that is not a product token (the board's page inset and swatch size).
private enum Layout {
    static let pageInsetV: CGFloat = 40
    static let pageInsetH: CGFloat = 48
    static let swatch: CGFloat = 28
    static let row: CGFloat = 28
    static let nameColumn: CGFloat = 124
    static let hexColumn: CGFloat = 54
    static let cssColumn: CGFloat = 100
    static let scaleColumn: CGFloat = 112
    static let metricColumn: CGFloat = 52
    static let weightColumn: CGFloat = 60
    static let radiusSample = CGSize(width: 28, height: 20)
}

private struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(title)
                .font(Font.Token.headline)
                .foregroundStyle(Color.textPrimary)
            content
        }
        .padding(.vertical, Spacing.l)
        .padding(.horizontal, Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceWindow, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.separator))
    }
}

private struct GroupHeading: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Font.Token.captionSemibold)
            .foregroundStyle(Color.textSecondary)
            .padding(.top, Spacing.s)
    }
}

/// A flat, un-bordered swatch on a one-point `separator` backing so white swatches stay visible on white.
private struct Swatch: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.m)
            .fill(color)
            .frame(width: Layout.swatch, height: Layout.swatch)
            .padding(1)
            .background(Color.separator, in: RoundedRectangle(cornerRadius: Radius.m + 1))
    }
}

private struct SwatchRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let token: Color.Token

    var body: some View {
        HStack(spacing: Spacing.s) {
            Swatch(color: token.color)
            Text(token.rawValue)
                .font(Font.Token.monoSmall)
                .foregroundStyle(Color.textPrimary)
                .frame(width: Layout.nameColumn, alignment: .leading)
            Text(token.lightHex)
                .font(Font.Token.monoSmall)
                .foregroundStyle(colorScheme == .dark ? Color.textTertiary : Color.textPrimary)
                .frame(width: Layout.hexColumn, alignment: .leading)
            Text(token.darkHex)
                .font(Font.Token.monoSmall)
                .foregroundStyle(colorScheme == .dark ? Color.textPrimary : Color.textTertiary)
                .frame(width: Layout.hexColumn, alignment: .leading)
            Text(token.cssVariable)
                .font(Font.Token.monoSmall)
                .foregroundStyle(Color.textTertiary)
                .frame(width: Layout.cssColumn, alignment: .leading)
            Text(token.use)
                .font(Font.Token.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(height: Layout.row)
    }
}

/// The system accent, shown so a reviewer can confirm it follows System Settings while `accent` does not.
private struct SelectionRow: View {
    var body: some View {
        HStack(spacing: Spacing.s) {
            Swatch(color: .accentColor)
            Text("selection")
                .font(Font.Token.monoSmall)
                .foregroundStyle(Color.textPrimary)
                .frame(width: Layout.nameColumn, alignment: .leading)
            Text("system accent")
                .font(Font.Token.monoSmall)
                .foregroundStyle(Color.textTertiary)
                .frame(width: Layout.hexColumn * 2 + Spacing.s, alignment: .leading)
            Text("--sel")
                .font(Font.Token.monoSmall)
                .foregroundStyle(Color.textTertiary)
                .frame(width: Layout.cssColumn, alignment: .leading)
            Text("Selected row and sidebar tint; follows System Settings")
                .font(Font.Token.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .frame(height: Layout.row)
    }
}

/// Dot, text and tint of every severity through the `Color.status…(_:)` helpers.
private struct SeverityStrip: View {
    var body: some View {
        HStack(spacing: Spacing.s) {
            ForEach(Severity.allCases, id: \.self) { severity in
                HStack(spacing: Spacing.xs + 2) {
                    Circle()
                        .fill(Color.statusDot(severity))
                        .frame(width: Size.statusDot, height: Size.statusDot)
                    Text(String(describing: severity))
                        .font(Font.Token.calloutMedium)
                        .foregroundStyle(Color.statusText(severity))
                }
                .padding(.horizontal, Spacing.s)
                .frame(height: Size.chip)
                .background(Color.statusTint(severity), in: RoundedRectangle(cornerRadius: Radius.s))
            }
            Text("dot · .text · .tint by Severity")
                .font(Font.Token.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, Spacing.xs)
    }
}

private struct TypeRow: View {
    let scale: Font.Token.Scale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Text(scale.rawValue)
                .font(Font.Token.monoSmall)
                .foregroundStyle(Color.textPrimary)
                .frame(width: Layout.scaleColumn, alignment: .leading)
            Text("\(Int(scale.size)) / \(Int(scale.lineHeight))")
                .font(Font.Token.callout)
                .foregroundStyle(Color.textSecondary)
                .frame(width: Layout.metricColumn, alignment: .leading)
            Text(weightName)
                .font(Font.Token.callout)
                .foregroundStyle(Color.textSecondary)
                .frame(width: Layout.weightColumn, alignment: .leading)
            Text(sample)
                .font(scale.font)
                .tracking(scale == .title ? Font.Token.titleTracking : 0)
                .foregroundStyle(scale.size < Font.Token.Scale.callout.size ? Color.textSecondary : Color.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, Spacing.xs + 2)
    }

    private var weightName: String {
        switch scale.weight {
        case .bold: "Bold"
        case .semibold: "Semibold"
        case .medium: "Medium"
        default: "Regular"
        }
    }

    private var sample: String {
        switch scale {
        case .title: "pdf — scope and skill names"
        case .headline: "Update pdf 1.2.0 → 1.4.0 (sheet titles)"
        case .body: "Default text. pdf will no longer be available to Claude Code in this project."
        case .bodyEmphasis: "Row titles, card titles"
        case .bodyMedium: "Button labels (medium)"
        case .callout: "Card lines, table cells, trailing row status"
        case .calloutMedium: "Filter chips, tabs, status labels"
        case .calloutSemibold: "Detail header state line"
        case .caption: "Row second line, footnotes. Nothing smaller exists."
        case .captionMedium: "Kind pills"
        case .captionSemibold: "Count badges"
        case .mono: "anthropics/skills · 1.2.0 → 1.4.0 · ~/work/api · diff and log text"
        case .monoSmall: "package name on a row’s second line"
        }
    }
}

private struct RadiusSample: View {
    let radius: CGFloat

    var body: some View {
        Group {
            if radius == Radius.pill {
                Capsule().stroke(Color.textPrimary, lineWidth: 1.5)
            } else {
                RoundedRectangle(cornerRadius: radius).stroke(Color.textPrimary, lineWidth: 1.5)
            }
        }
        .frame(width: Layout.radiusSample.width, height: Layout.radiusSample.height)
    }
}

private struct SizeCell: View {
    let name: String
    let value: String

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(name)
                .font(Font.Token.monoSmall)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 0)
            Text(value)
                .font(Font.Token.monoSmall)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

#Preview("Tokens, light") {
    TokensPreview().frame(width: 1280, height: 1560)
}

#Preview("Tokens, dark") {
    TokensPreview().frame(width: 1280, height: 1560).preferredColorScheme(.dark)
}
