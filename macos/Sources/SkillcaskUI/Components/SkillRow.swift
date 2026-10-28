import SkillcaskDomain
import SwiftUI

/// One row of the skills list (Main and Components boards, "Skill row"): the status dot, the name with its version
/// in mono, a second line saying where the skill comes from (`SkillRowSecondary`) and a trailing slot that says
/// exactly one thing (`SkillRowTrailing`). 52 pt tall (`Size.row`), one `Spacing.rowGap` between the parts.
///
/// Selection: inside a `List(selection:)` the system draws the accent highlight and raises
/// `backgroundProminence` for the selected row, which turns the text white and the source pill translucent;
/// `isSelected` forces the same emphasis for a row drawn on its own (the component sheet, previews). The row
/// never paints a selection colour itself, so the highlight is always the system's, including when the window is
/// inactive. `isOffline` hides what only `outdated` knows. Stale while refreshing is not the row's: the boards fade
/// the whole list, selection included, so the list screen applies `staleOpacity` to its `List`.
public struct SkillRow: View {
    public let entry: SkillEntry
    public let isSelected: Bool
    public let isOffline: Bool
    /// The skills that require a dependency row (`ScopeSnapshot.requirerSkills(of:)`); nil or empty falls back to
    /// the `via` package names.
    public let requiredBy: [String]?

    @Environment(\.backgroundProminence) private var prominence

    public init(_ entry: SkillEntry, isSelected: Bool = false, isOffline: Bool = false, requiredBy: [String]? = nil) {
        self.entry = entry
        self.isSelected = isSelected
        self.isOffline = isOffline
        self.requiredBy = requiredBy
    }

    /// The row height, `.row{height:52px}`.
    public static let height = Size.row
    /// "Stale while refreshing: rows at 50 % opacity" (List-States board): applied by the list screen to the whole
    /// list, so the selected row's accent fades with the rest.
    public static let staleOpacity: Double = 0.5
    /// The row's `padding: 0 12px 0 14px`: 14 before the dot is the card's horizontal padding token (the one 14 pt
    /// metric of the Tokens board), 12 after the trailing slot is `Spacing.m`.
    public static let leadingPadding = Size.cardPaddingH
    public static let trailingPadding = Spacing.m

    /// The boards' selected-row text, `#fff`, `rgba(255,255,255,0.82)` and the version's `opacity: 0.85`: not
    /// tokens (tokens.md G5), the white that every system accent is designed to carry.
    static let selectedPrimary = Color.white
    static let selectedSecondary = Color.white.opacity(0.82)
    static let selectedVersion = Color.white.opacity(0.85)
    /// The ring around the dot of the selected row (`box-shadow: 0 0 0 2px rgba(255,255,255,0.35)`).
    static let selectedDotRing = Color.white.opacity(0.35)
    static let selectedDotRingWidth: CGFloat = 2

    /// The warning glyph before `N findings` (the boards' 12 pt triangle).
    static let findingsSymbol = "exclamationmark.triangle"

    public var body: some View {
        HStack(spacing: Spacing.rowGap) {
            dot
            column
            trailingSlot
        }
        .padding(.leading, Self.leadingPadding)
        .padding(.trailing, Self.trailingPadding)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .environment(\.backgroundProminence, emphasized ? .increased : .standard)
        .accessibilityElement(children: .combine)
        .accessibilityValue(secondary.text)
    }

    // MARK: - Derived

    var trailing: SkillRowTrailing {
        .resolve(entry, offline: isOffline)
    }

    var secondary: SkillRowSecondary {
        .resolve(entry, requiredBy: requiredBy)
    }

    private var emphasized: Bool {
        isSelected || prominence == .increased
    }

    private var primaryColor: Color {
        emphasized ? Self.selectedPrimary : Color.textPrimary
    }

    private var secondaryColor: Color {
        emphasized ? Self.selectedSecondary : Color.textSecondary
    }

    private var versionColor: Color {
        emphasized ? Self.selectedVersion : Color.textSecondary
    }

    private var statusColor: Color {
        if emphasized {
            return Self.selectedSecondary
        }
        return trailing.isQuiet ? Color.textSecondary : Color.statusText(trailing.severity)
    }

    // MARK: - Subviews

    private var dot: some View {
        StatusDot(trailing.severity)
            .background {
                if emphasized {
                    Circle()
                        .strokeBorder(Self.selectedDotRing, lineWidth: Self.selectedDotRingWidth)
                        .frame(
                            width: Size.statusDot + 2 * Self.selectedDotRingWidth,
                            height: Size.statusDot + 2 * Self.selectedDotRingWidth)
                }
            }
    }

    /// `flex: 1; min-width: 0`: takes what the dot and the trailing slot leave, and truncates its own text first.
    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.inline) {
                Text(entry.name)
                    .font(Font.Token.bodyEmphasis)
                    .foregroundStyle(primaryColor)
                if let version = entry.version {
                    Text(version)
                        .font(Font.Token.mono)
                        .foregroundStyle(versionColor)
                }
            }
            .lineLimit(1)
            secondaryLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var secondaryLine: some View {
        switch secondary {
        case .location(let location, let source):
            HStack(spacing: Spacing.inline) {
                if let location {
                    Text(location)
                        .font(Font.Token.monoSmall)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let source {
                    Pill(source: source)
                }
            }
        case .requiredBy(let names):
            Text(Labels.requiredBy(names))
                .font(Font.Token.caption)
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
        }
    }

    /// Keeps its natural width (`layoutPriority`), so the column truncates before the slot ever does.
    @ViewBuilder private var trailingSlot: some View {
        Group {
            switch trailing {
            case .update:
                Text(trailing.label).font(Font.Token.monoSmall)
            case .findings:
                HStack(spacing: Spacing.xs) {
                    Image(systemName: Self.findingsSymbol)
                    Text(trailing.label)
                }
                .font(Font.Token.calloutMedium)
            case .dependency, .state:
                Text(trailing.label).font(trailing.isQuiet ? Font.Token.callout : Font.Token.calloutMedium)
            }
        }
        .foregroundStyle(statusColor)
        .lineLimit(1)
        .fixedSize()
        .layoutPriority(1)
    }
}

#Preview("SkillRow, light") {
    VStack(spacing: 0) {
        SkillRow(DesignFixtures.commitMessage)
        SkillRow(DesignFixtures.pdf)
        SkillRow(DesignFixtures.pdf, isSelected: true)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Radius.m))
        SkillRow(DesignFixtures.myNotes)
        SkillRow(
            DesignFixtures.safeRefactor, requiredBy: DesignFixtures.api.requirerSkills(of: DesignFixtures.safeRefactor))
        SkillRow(DesignFixtures.deployChecklist)
        SkillRow(DesignFixtures.caveman, isOffline: true)
    }
    .frame(width: Size.listWidth)
    .padding(Spacing.s)
    .background(Color.surfaceWindow)
}

#Preview("SkillRow, dark") {
    VStack(spacing: 0) {
        SkillRow(DesignFixtures.commitMessage)
        SkillRow(DesignFixtures.pdf)
        SkillRow(DesignFixtures.pdf, isSelected: true)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Radius.m))
        SkillRow(DesignFixtures.myNotes)
        SkillRow(
            DesignFixtures.safeRefactor, requiredBy: DesignFixtures.api.requirerSkills(of: DesignFixtures.safeRefactor))
        SkillRow(DesignFixtures.deployChecklist)
        SkillRow(DesignFixtures.caveman, isOffline: true)
    }
    .frame(width: Size.listWidth)
    .padding(Spacing.s)
    .background(Color.surfaceWindow)
    .preferredColorScheme(.dark)
}
