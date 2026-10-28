import SwiftUI

extension Font {
    /// The type scale of the Tokens board: SF Pro Text for everything, SF Mono only for what the user meets
    /// verbatim in a repository (package names, versions, paths, file names, diff and transcript text).
    ///
    /// A namespace rather than members of `Font`, because `Font.title`, `.headline`, `.body`, `.callout` and
    /// `.caption` already exist and must not be shadowed. Nothing is smaller than 11 pt, and 11 pt text is
    /// `Color.textSecondary` or darker.
    public enum Token {
        /// `type.title` · 22 / 28 · Bold: scope and skill names (detail header, Overview heading).
        public static let title = Scale.title.font
        /// `type.sheetTitle` · 20 / 26 · Bold: the onboarding sheet's title (Onboarding boards, `h2 font-size: 20px;
        /// line-height: 26px; font-weight: 700`).
        public static let sheetTitle = Scale.sheetTitle.font
        /// `type.headline` · 15 / 20 · Semibold: sheet titles, empty-state titles.
        public static let headline = Scale.headline.font
        /// `type.body` · 13 / 18 · Regular: default text, key/value rows, buttons.
        public static let body = Scale.body.font
        /// `type.body.emphasis` · 13 / 18 · Semibold: row titles, card titles.
        public static let bodyEmphasis = Scale.bodyEmphasis.font
        /// `type.body` at Medium (500): push-button labels (board `.btn`, gap G11).
        public static let bodyMedium = Scale.bodyMedium.font
        /// `type.callout` · 12 / 16 · Regular: card lines, table cells, trailing row status.
        public static let callout = Scale.callout.font
        /// `type.callout` at Medium (500): filter chips, segmented tabs, status labels (gap G11).
        public static let calloutMedium = Scale.calloutMedium.font
        /// `type.callout` at Semibold (600): the Detail-States header state line (`font-size: 12px; font-weight: 600`).
        public static let calloutSemibold = Scale.calloutSemibold.font
        /// `type.caption` · 11 / 14 · Regular: row second line, footnotes.
        public static let caption = Scale.caption.font
        /// `type.caption` at Medium (500): kind pills (gap G11).
        public static let captionMedium = Scale.captionMedium.font
        /// `type.caption` at Semibold (600): count badges (gap G11).
        public static let captionSemibold = Scale.captionSemibold.font
        /// `type.mono` · 12 / 16 · Regular, SF Mono: `anthropics/skills · 1.2.0 → 1.4.0`, diff and log text.
        public static let mono = Scale.mono.font
        /// `type.mono.small` · 11 / 14 · Regular, SF Mono: the package name on a row's second line.
        public static let monoSmall = Scale.monoSmall.font

        /// The board's `letter-spacing: -0.01em` on `type.title`, in points at 22 pt; apply with `.tracking(_:)`.
        public static let titleTracking: CGFloat = -0.22

        /// Line heights the boards fix outside the scale.
        public enum LineHeight {
            /// The diff grid draws `type.mono.small` on an 18 pt line (Components `.sc .dl`, gap G13; P2-9).
            public static let diff: CGFloat = 18
            /// The Activity transcript draws `type.mono.small` on a 15 pt line (Activity board `.mono` with
            /// `line-height: 15px`), as G13 records for the diff grid's 18 pt.
            public static let transcript: CGFloat = 15
        }

        /// Every entry of the scale with its metrics, so the token sheet and the tests can enumerate it.
        public enum Scale: String, CaseIterable, Sendable {
            case title
            case sheetTitle
            case headline
            case body
            case bodyEmphasis
            case bodyMedium
            case callout
            case calloutMedium
            case calloutSemibold
            case caption
            case captionMedium
            case captionSemibold
            case mono
            case monoSmall

            /// Point size.
            public var size: CGFloat {
                switch self {
                case .title: 22
                case .sheetTitle: 20
                case .headline: 15
                case .body, .bodyEmphasis, .bodyMedium: 13
                case .callout, .calloutMedium, .calloutSemibold, .mono: 12
                case .caption, .captionMedium, .captionSemibold, .monoSmall: 11
                }
            }

            /// Line height in points, as the board states it (`size / line`).
            public var lineHeight: CGFloat {
                switch self {
                case .title: 28
                case .sheetTitle: 26
                case .headline: 20
                case .body, .bodyEmphasis, .bodyMedium: 18
                case .callout, .calloutMedium, .calloutSemibold, .mono: 16
                case .caption, .captionMedium, .captionSemibold, .monoSmall: 14
                }
            }

            public var weight: Font.Weight {
                switch self {
                case .title, .sheetTitle: .bold
                case .headline, .bodyEmphasis, .calloutSemibold, .captionSemibold: .semibold
                case .bodyMedium, .calloutMedium, .captionMedium: .medium
                case .body, .callout, .caption, .mono, .monoSmall: .regular
                }
            }

            public var design: Font.Design {
                switch self {
                case .mono, .monoSmall: .monospaced
                default: .default
                }
            }

            public var font: Font { .system(size: size, weight: weight, design: design) }
        }
    }
}
