import SkillcaskDomain

/// The second line of a skill row: where the skill comes from. The Main and Components boards draw a location
/// in mono (`anthropics/skills`, `.skills/my-notes`, `juliusbrussee/caveman`) with the source pill after it, and
/// `Required by caveman` for a dependency. Pure: `resolve` reads a `SkillEntry`.
public enum SkillRowSecondary: Hashable, Sendable {
    /// A location in `Font.Token.monoSmall` and the source pill; either may be missing when the CLI printed none.
    case location(String?, source: SourceKind?)
    /// `Required by caveman`: a dependency names what pulls it in instead of a source.
    case requiredBy([String])

    /// A package row shows its package name; a project or local skill its path (from `audit`); a not managed row
    /// the location of its `adopt` spec, else its path. The pill is `SourceKind.kind(of:)`. A dependency names
    /// `requiredBy`, the skills that require it (`ScopeSnapshot.requirerSkills(of:)`, the board's "Required by
    /// caveman"); when the caller has none, the `via` package names of its kind stand in (Q10 interim).
    public static func resolve(_ entry: SkillEntry, requiredBy: [String]? = nil) -> SkillRowSecondary {
        let source = SourceKind.kind(of: entry)
        switch entry.kind {
        case .dependency(_, let via):
            return .requiredBy(requiredBy.flatMap { $0.isEmpty ? nil : $0 } ?? via)
        case .package(let name), .packageOnly(let name):
            return .location(name, source: source)
        case .project, .handWritten:
            return .location(entry.path, source: source)
        case .notManaged:
            return .location(entry.adoptLocation ?? entry.path, source: source)
        }
    }

    /// The line as one string: `anthropics/skills · GitHub` (as `List-States` writes it, and what assistive
    /// technology reads), `Required by caveman`.
    public var text: String {
        switch self {
        case .location(let location, let source): RowCopy.secondary(location: location, source: source)
        case .requiredBy(let names): Labels.requiredBy(names)
        }
    }
}
