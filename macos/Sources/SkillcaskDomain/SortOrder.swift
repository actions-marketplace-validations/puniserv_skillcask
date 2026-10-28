/// The list's sort menu (S2 note: "sort menu: Name, State (worst first), Source"). `apply` orders entries; the
/// filter and the query are `Filter.apply`'s, which sorts by `.state` on its own so callers that take no sort
/// keep the worst-first order.
public enum SortOrder: String, CaseIterable, Hashable, Sendable {
    /// Alphabetical by skill name.
    case name
    /// Worst health first (`Severity`), then by name: the default and what `Filter.apply` does.
    case state
    /// By source kind (Packagist, GitHub, git, skills.sh, custom names, project, local, unknown last), then name.
    case source

    /// `entries` in this order; stable for equal keys because the tiebreak is the name.
    public func apply(_ entries: [SkillEntry]) -> [SkillEntry] {
        switch self {
        case .name:
            return entries.sorted(by: Self.byName)
        case .state:
            return entries.sorted { lhs, rhs in
                if lhs.health.severity != rhs.health.severity {
                    return lhs.health.severity > rhs.health.severity
                }
                return Self.byName(lhs, rhs)
            }
        case .source:
            return entries.sorted { lhs, rhs in
                let left = Self.sourceRank(of: lhs)
                let right = Self.sourceRank(of: rhs)
                if left != right {
                    return left < right
                }
                return Self.byName(lhs, rhs)
            }
        }
    }

    static func byName(_ lhs: SkillEntry, _ rhs: SkillEntry) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    /// A sortable key for a source: the kind's position in the list above, then a custom repository's name;
    /// a row without a source sorts last.
    static func sourceRank(of entry: SkillEntry) -> (Int, String) {
        switch SourceKind.kind(of: entry) {
        case .packagist: (0, "")
        case .github: (1, "")
        case .git: (2, "")
        case .skillsSh: (3, "")
        case .custom(let name): (4, name.lowercased())
        case .project: (5, "")
        case .local: (6, "")
        case nil: (7, "")
        }
    }
}
