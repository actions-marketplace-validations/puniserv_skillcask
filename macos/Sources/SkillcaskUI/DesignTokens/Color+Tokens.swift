import AppKit
import SkillcaskDomain
import SwiftUI

/// The colour tokens of the Tokens board (tabulated in `macos/DESIGN.md`).
///
/// Every token is one dynamic colour whose light and dark values are the board's hex, sRGB, resolved by
/// `NSAppearance` at draw time; this file is the only place in `SkillcaskUI` that may spell a hex value.
/// Selection is deliberately absent: rows and the sidebar use `Color.accentColor` as the system draws it.
extension Color {
    // MARK: - Surfaces

    /// `--win` · `surface.window`: list, detail, sheets.
    public static let surfaceWindow = Token.surfaceWindow.color
    /// `--side` · `surface.sidebar`: sidebar (system material in SwiftUI).
    public static let surfaceSidebar = Token.surfaceSidebar.color
    /// `--grouped` · `surface.grouped`: Overview background, segmented control track.
    public static let surfaceGrouped = Token.surfaceGrouped.color
    /// `--card` · `surface.card`: cards on the grouped background; dark is lighter than the ground, never shadowed.
    public static let surfaceCard = Token.surfaceCard.color
    /// `--hover` · `surface.hover`: row hover.
    public static let surfaceHover = Token.surfaceHover.color
    /// `--sep` · `separator`: hairlines, card borders.
    public static let separator = Token.separator.color
    /// `--sep2` · `separator.strong`: chip borders, window edge.
    public static let separatorStrong = Token.separatorStrong.color

    // MARK: - Text

    /// `--text` · `text.primary`: 16.4:1 on the window (light), 15.6:1 (dark).
    public static let textPrimary = Token.textPrimary.color
    /// `--text2` · `text.secondary`: the only grey allowed for 11 pt text (6.2:1 light, 7.0:1 dark).
    public static let textSecondary = Token.textSecondary.color
    /// `--text3` · `text.tertiary`: icons and placeholders only, never body text.
    public static let textTertiary = Token.textTertiary.color

    // MARK: - Controls

    /// `--ctrl` · `control.fill`: push buttons, fields, segmented controls.
    public static let controlFill = Token.controlFill.color
    /// `--ctrl-b` · `control.border`: push buttons, fields, segmented controls.
    public static let controlBorder = Token.controlBorder.color

    // MARK: - Brand accent · Iris

    /// `--accent` · `accent`: primary buttons, links, the active filter chip, sidebar glyphs. Not `accentColor`.
    public static let accent = Token.accent.color
    /// `--accent-soft` · `accent.soft`: active filter chip fill.
    public static let accentSoft = Token.accentSoft.color
    /// `--accent-line` · `accent.line`: the border of the app-update card (U1); never `status.update`.
    public static let accentLine = Token.accentLine.color

    // MARK: - Status (dot · text · tint)

    /// `--ok` · `status.ok`: the 8 pt dot and badge fill; never text.
    public static let statusOkDot = Token.statusOkDot.color
    /// `--ok-t` · `status.ok.text`: text in the ok colour (4.5:1 on its surface).
    public static let statusOkText = Token.statusOkText.color
    /// `--ok-tint` · `status.ok.tint`: the surface behind an ok label.
    public static let statusOkTint = Token.statusOkTint.color
    /// `--upd` · `status.update`: the 8 pt dot and badge fill; never text.
    public static let statusUpdateDot = Token.statusUpdateDot.color
    /// `--upd-t` · `status.update.text`: text in the update colour.
    public static let statusUpdateText = Token.statusUpdateText.color
    /// `--upd-tint` · `status.update.tint`: the surface behind an update label.
    public static let statusUpdateTint = Token.statusUpdateTint.color
    /// `--warn` · `status.warning`: the 8 pt dot and badge fill; never text.
    public static let statusWarningDot = Token.statusWarningDot.color
    /// `--warn-t` · `status.warning.text`: text in the warning colour.
    public static let statusWarningText = Token.statusWarningText.color
    /// `--warn-tint` · `status.warning.tint`: the surface behind a warning label.
    public static let statusWarningTint = Token.statusWarningTint.color
    /// `--err` · `status.error`: the 8 pt dot and badge fill; never text.
    public static let statusErrorDot = Token.statusErrorDot.color
    /// `--err-t` · `status.error.text`: text in the error colour.
    public static let statusErrorText = Token.statusErrorText.color
    /// `--err-tint` · `status.error.tint`: the surface behind an error label.
    public static let statusErrorTint = Token.statusErrorTint.color
    /// `--neu` · `status.neutral`: the 8 pt dot; never text.
    public static let statusNeutralDot = Token.statusNeutralDot.color
    /// `--neu-t` · `status.neutral.text`: text in the neutral colour (same values as `text.secondary`).
    public static let statusNeutralText = Token.statusNeutralText.color
    /// `--neu-tint` · `status.neutral.tint`: the surface behind a neutral label.
    public static let statusNeutralTint = Token.statusNeutralTint.color

    // MARK: - Pill and skeleton

    /// `--pill` · `pill.fill`: the fill of a kind pill ("package", "project").
    public static let pillFill = Token.pillFill.color
    /// `--pill-t` · `pill.text`: the text of a kind pill.
    public static let pillText = Token.pillText.color
    /// `--skel` · `skeleton`: loading placeholder bars.
    public static let skeleton = Token.skeleton.color

    // MARK: - Secondary selection and diff

    /// `--sel-soft` · `selection.soft`: a selected row in an inactive list or a secondary selection.
    public static let selectionSoft = Token.selectionSoft.color
    /// `--diff-add` · `diff.added`: the background of an added diff line.
    public static let diffAdded = Token.diffAdded.color
    /// `--diff-del` · `diff.removed`: the background of a removed diff line.
    public static let diffRemoved = Token.diffRemoved.color
    /// `--diff-risk` · `diff.risk`: the background of a diff line with a risky pattern.
    public static let diffRisk = Token.diffRisk.color
    /// `--diff-inv` · `diff.invisible`: the background of a diff line with an invisible character.
    public static let diffInvisible = Token.diffInvisible.color

    // MARK: - Badge text

    /// `badge.warning.text`: the count on an amber badge, "dark text (4.6:1 on amber)" (Components board). The
    /// boards inline the hex rather than naming a var (gap G5); the same value in both appearances. Every other
    /// badge fill takes white text.
    public static let badgeWarningText = Token.badgeWarningText.color

    // MARK: - Severity

    /// The dot colour of a severity: the only use of the `.dot` tokens besides badge fills.
    public static func statusDot(_ severity: Severity) -> Color {
        switch severity {
        case .neutral: .statusNeutralDot
        case .ok: .statusOkDot
        case .update: .statusUpdateDot
        case .warning: .statusWarningDot
        case .error: .statusErrorDot
        }
    }

    /// The text colour of a severity: every label drawn in a status colour uses this.
    public static func statusText(_ severity: Severity) -> Color {
        switch severity {
        case .neutral: .statusNeutralText
        case .ok: .statusOkText
        case .update: .statusUpdateText
        case .warning: .statusWarningText
        case .error: .statusErrorText
        }
    }

    /// The tint of a severity: the surface behind a status label or callout.
    public static func statusTint(_ severity: Severity) -> Color {
        switch severity {
        case .neutral: .statusNeutralTint
        case .ok: .statusOkTint
        case .update: .statusUpdateTint
        case .warning: .statusWarningTint
        case .error: .statusErrorTint
        }
    }

    // MARK: - Catalog

    /// Every colour token by name, in board order, with the hex the board states for each appearance; the token
    /// sheet and the tests enumerate this, components use the `Color` statics above.
    public enum Token: String, CaseIterable, Sendable {
        case surfaceWindow
        case surfaceSidebar
        case surfaceGrouped
        case surfaceCard
        case surfaceHover
        case separator
        case separatorStrong
        case textPrimary
        case textSecondary
        case textTertiary
        case controlFill
        case controlBorder
        case accent
        case accentSoft
        case accentLine
        case statusOkDot
        case statusOkText
        case statusOkTint
        case statusUpdateDot
        case statusUpdateText
        case statusUpdateTint
        case statusWarningDot
        case statusWarningText
        case statusWarningTint
        case statusErrorDot
        case statusErrorText
        case statusErrorTint
        case statusNeutralDot
        case statusNeutralText
        case statusNeutralTint
        case pillFill
        case pillText
        case skeleton
        case selectionSoft
        case diffAdded
        case diffRemoved
        case diffRisk
        case diffInvisible
        case badgeWarningText

        /// The CSS custom property every screen board uses for this token (`badgeWarningText` has none: the boards
        /// inline its hex, so the name here is the proposed one).
        public var cssVariable: String { spec.css }
        /// The light-appearance hex, character-exact from the board (`#RRGGBB`).
        public var lightHex: String { spec.light }
        /// The dark-appearance hex, character-exact from the board (`#RRGGBB`).
        public var darkHex: String { spec.dark }
        /// Where the board uses the token, quoted.
        public var use: String { spec.use }
        /// The dynamic colour: light hex under `.aqua`, dark hex under `.darkAqua`.
        public var color: Color { Color(light: spec.light, dark: spec.dark) }

        private var spec: Spec {
            switch self {
            case .surfaceWindow: Spec("--win", "#FFFFFF", "#1E1E1E", "List, detail, sheets")
            case .surfaceSidebar: Spec("--side", "#F2F2F4", "#272729", "Sidebar (system material in SwiftUI)")
            case .surfaceGrouped: Spec("--grouped", "#F5F5F7", "#232325", "Overview background, segmented track")
            case .surfaceCard: Spec("--card", "#FFFFFF", "#2A2A2C", "Cards: lighter than ground, no shadow")
            case .surfaceHover: Spec("--hover", "#F2F2F5", "#2A2A2D", "Row hover")
            case .separator: Spec("--sep", "#E3E3E8", "#353538", "Hairlines, card borders")
            case .separatorStrong: Spec("--sep2", "#D1D1D6", "#454549", "Chip borders, window edge")
            case .textPrimary: Spec("--text", "#1D1D1F", "#F5F5F7", "16.4:1 on window · 15.6:1 dark")
            case .textSecondary: Spec("--text2", "#5E5E63", "#A1A1A6", "The only grey allowed for 11 pt text")
            case .textTertiary: Spec("--text3", "#8A8A8F", "#7C7C82", "Icons and placeholders only")
            case .controlFill: Spec("--ctrl", "#FFFFFF", "#333336", "Push buttons, fields, segmented")
            case .controlBorder: Spec("--ctrl-b", "#CFCFD4", "#48484C", "Push buttons, fields, segmented")
            case .accent: Spec("--accent", "#6D4AFF", "#8B74FF", "Primary buttons, links, active filter")
            case .accentSoft: Spec("--accent-soft", "#EEE9FF", "#2E2750", "Active filter chip fill")
            case .accentLine: Spec("--accent-line", "#CFC3FF", "#4A3F86", "App-update card border")
            case .statusOkDot: Spec("--ok", "#34C759", "#30D158", "Dot, badge fill")
            case .statusOkText: Spec("--ok-t", "#1B7A35", "#4CD964", "Installed · Project skill · Linked")
            case .statusOkTint: Spec("--ok-tint", "#E9F8EC", "#17301D", "Surface behind an ok label")
            case .statusUpdateDot: Spec("--upd", "#0A7AFF", "#409CFF", "Dot, update badge fill")
            case .statusUpdateText: Spec("--upd-t", "#0A5FCC", "#6EB2FF", "→ 1.4.0")
            case .statusUpdateTint: Spec("--upd-tint", "#E6F1FF", "#172A44", "Surface behind an update label")
            case .statusWarningDot: Spec("--warn", "#F5A623", "#FFB340", "Dot, badge fill")
            case .statusWarningText: Spec("--warn-t", "#8A5A00", "#FFC24A", "Not managed · 2 findings")
            case .statusWarningTint: Spec("--warn-tint", "#FFF5DF", "#3A2C10", "Surface behind a warning label")
            case .statusErrorDot: Spec("--err", "#FF3B30", "#FF6961", "Dot, badge fill")
            case .statusErrorText: Spec("--err-t", "#C42B22", "#FF7B72", "Needs sync · Not installed")
            case .statusErrorTint: Spec("--err-tint", "#FFECEA", "#3D1F1D", "Surface behind an error label")
            case .statusNeutralDot: Spec("--neu", "#8E8E93", "#98989D", "Dot")
            case .statusNeutralText: Spec("--neu-t", "#5E5E63", "#A1A1A6", "Dependency · Required by caveman")
            case .statusNeutralTint: Spec("--neu-tint", "#F0F0F2", "#2C2C2E", "Surface behind a neutral label")
            case .pillFill: Spec("--pill", "#ECECF0", "#38383C", "Kind pill fill")
            case .pillText: Spec("--pill-t", "#3A3A3F", "#D5D5DA", "Kind pill text")
            case .skeleton: Spec("--skel", "#E8E8EC", "#333336", "Loading placeholder bars")
            case .selectionSoft: Spec("--sel-soft", "#DCE8FF", "#1E3A66", "Inactive or secondary selection")
            case .diffAdded: Spec("--diff-add", "#E6F6EA", "#1B3323", "Added diff line")
            case .diffRemoved: Spec("--diff-del", "#FDE8E6", "#3B1F1F", "Removed diff line")
            case .diffRisk: Spec("--diff-risk", "#FFF0C2", "#3A2F10", "Diff line with a risky pattern")
            case .diffInvisible: Spec("--diff-inv", "#F3E8FF", "#2E2444", "Diff line with an invisible character")
            case .badgeWarningText: Spec("--badge-warn-t", "#3B2600", "#3B2600", "Count on an amber badge")
            }
        }
    }

    /// One board row: CSS var, light hex, dark hex, use.
    private struct Spec {
        let css: String
        let light: String
        let dark: String
        let use: String

        init(_ css: String, _ light: String, _ dark: String, _ use: String) {
            self.css = css
            self.light = light
            self.dark = dark
            self.use = use
        }
    }

    /// The one constructor of every token: an `NSColor` dynamic provider that picks the light or dark sRGB value
    /// by the appearance's best match, so the colour follows the window, a hosting view or a preview's scheme.
    private init(light: String, dark: String) {
        let lightChannels = Channels(hex: light)
        let darkChannels = Channels(hex: dark)
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let channels =
                    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkChannels : lightChannels
                return NSColor(srgbRed: channels.red, green: channels.green, blue: channels.blue, alpha: 1)
            })
    }

    /// `#RRGGBB` split into unit channels; a malformed token is a programming error caught by the token tests.
    private struct Channels: Sendable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        init(hex: String) {
            let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
                fatalError("design token \(hex) is not #RRGGBB")
            }
            red = CGFloat((value >> 16) & 0xFF) / 255
            green = CGFloat((value >> 8) & 0xFF) / 255
            blue = CGFloat(value & 0xFF) / 255
        }
    }
}
