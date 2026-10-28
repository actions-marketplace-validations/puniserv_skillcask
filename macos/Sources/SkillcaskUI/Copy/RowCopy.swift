import SkillcaskDomain

/// The second line and the trailing slot of a skill row, verbatim from the Main, Components and List-States
/// boards: `anthropics/skills · GitHub`, `→ 1.4.0`, `Dependency`. The state words come from `Labels`, the source
/// names from `SourceCopy`, the adopt location from Domain (`SkillEntry.adoptLocation`); this file only joins and
/// prefixes them.
public enum RowCopy {
    /// The middle dot between a location and its source when the second line is text (`List-States` writes
    /// `anthropics/skills · GitHub`; the row also reads so to assistive technology).
    public static let separator = " · "

    /// `anthropics/skills · GitHub`: the parts the row has, joined; empty when it has neither.
    public static func secondary(location: String?, source: SourceKind?) -> String {
        [location, source.map(SourceCopy.label)].compactMap { $0 }.joined(separator: separator)
    }

    /// `→ 1.4.0`: the trailing slot of a row with an update. The arrow is text, as in `Labels.versionTransition`,
    /// so it copies.
    public static func arrow(to version: String) -> String {
        "→ \(version)"
    }

    /// `Dependency`: the trailing word of a healthy dependency row; the kind label, whichever package requires it.
    public static let dependency = Labels.kind(.dependency("", via: []))
}
