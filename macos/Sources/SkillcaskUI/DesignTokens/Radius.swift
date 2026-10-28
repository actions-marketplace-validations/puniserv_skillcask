import Foundation

/// The corner radii of the Tokens board, in points.
public enum Radius {
    /// `radius.s`: badges, pills.
    public static let s: CGFloat = 4
    /// `radius.m`: controls, rows.
    public static let m: CGFloat = 6
    /// `radius.l`: cards, callouts.
    public static let l: CGFloat = 8
    /// `radius.xl`: sheets.
    public static let xl: CGFloat = 10
    /// `radius.pill`: filter chips; draw with `Capsule()`, the value only names the intent.
    public static let pill: CGFloat = 999
    /// The mini progress bar under a refreshing list header (`List-States`: 3 pt tall, radius 2).
    public static let miniProgress: CGFloat = 2

    /// The radii in board order, for the token sheet and the tests.
    public static let catalog: [(name: String, value: CGFloat)] = [
        ("radius.s", s), ("radius.m", m), ("radius.l", l), ("radius.xl", xl), ("radius.pill", pill),
        ("miniProgress", miniProgress),
    ]
}
