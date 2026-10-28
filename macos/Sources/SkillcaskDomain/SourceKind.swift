/// Where a skill comes from, read from the strings the CLI prints: `status.source` (planned; the repository
/// name or `git`), `status.repositories[].name` (`packagist`, `github`, a custom name), `info.source` and
/// `search.source` (`packagist`, `composer`, `github`, `git`, `skills.sh`), and the `adopt` spec of a not
/// managed row (`github:owner/repo`, `git:https://…`, D38). The interface shows one glyph and one name per kind.
public enum SourceKind: Hashable, Sendable {
    case packagist
    case github
    case git
    case skillsSh
    /// A custom repository, by its configured name.
    case custom(String)
    case project
    case local

    /// Reads a CLI source string. `packagist` and `composer` (the repository type) are Packagist; `github` or a
    /// `github:` spec is GitHub; `git`, a `git:` spec, an `git@` remote or a `.git` URL is a plain git source;
    /// `skills.sh` (also `skills-sh`, the JSON key) is the skills.sh index; `project` and `local` name the two
    /// unmanaged kinds; anything else is a custom repository named by the string. Case and surrounding
    /// whitespace are ignored; a custom name keeps its spelling.
    public init(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        if lower == "packagist" || lower == "composer" {
            self = .packagist
        } else if lower == "github" || lower.hasPrefix("github:") {
            self = .github
        } else if lower == "git" || lower.hasPrefix("git:") || lower.hasPrefix("git@") || lower.hasSuffix(".git") {
            self = .git
        } else if lower == "skills.sh" || lower == "skills-sh" {
            self = .skillsSh
        } else if lower == "project" {
            self = .project
        } else if lower == "local" {
            self = .local
        } else {
            self = .custom(trimmed)
        }
    }

    /// The kind of a row: project and hand-written skills from their `Kind`, a not managed row from its `adopt`
    /// spec, otherwise the entry's `source`; nil when the CLI printed no source for a package row.
    public static func kind(of entry: SkillEntry) -> SourceKind? {
        switch entry.kind {
        case .project: return .project
        case .handWritten: return .local
        case .notManaged(let adopt):
            guard let adopt else { return entry.source.map(SourceKind.init(parsing:)) }
            return SourceKind(parsing: adopt)
        case .package, .dependency, .packageOnly:
            return entry.source.map(SourceKind.init(parsing:))
        }
    }
}
