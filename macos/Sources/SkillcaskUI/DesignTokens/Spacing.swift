import Foundation

/// The spacing scale of the Tokens board (`space.1 … space.7`), in points.
public enum Spacing {
    /// `space.1`
    public static let xs: CGFloat = 4
    /// `space.2`
    public static let s: CGFloat = 8
    /// `space.3`
    public static let m: CGFloat = 12
    /// `space.4`
    public static let l: CGFloat = 16
    /// `space.5`
    public static let xl: CGFloat = 20
    /// `space.6`
    public static let xxl: CGFloat = 24
    /// `space.7`
    public static let xxxl: CGFloat = 32
    /// The Overview card grid gap (`Overview-States` `gap: 10px`); off the scale, so named rather than written.
    public static let cardGap: CGFloat = 10
    /// The gap between a glyph and its words on one line: status dot and label, button icon and title, row name
    /// and version (`gap: 6px` on Components, Detail-States and Main); off the scale, so named rather than written.
    public static let inline: CGFloat = 6
    /// The gap between the status dot and the text column of a skill row (`gap: 10px` on Main, Components and
    /// List-States); off the scale, so named rather than written.
    public static let rowGap: CGFloat = 10

    /// The scale in board order, for the token sheet and the tests.
    public static let catalog: [(name: String, value: CGFloat)] = [
        ("space.1 · xs", xs), ("space.2 · s", s), ("space.3 · m", m), ("space.4 · l", l), ("space.5 · xl", xl),
        ("space.6 · xxl", xxl), ("space.7 · xxxl", xxxl), ("cardGap", cardGap), ("inline", inline),
        ("rowGap", rowGap),
    ]
}
