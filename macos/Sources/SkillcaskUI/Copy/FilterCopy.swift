import SkillcaskDomain

/// The titles of the filter chips above the list, verbatim from the Components board ("Filter chips and
/// buttons"). Views never spell these; `FilterChipBar` reads them here.
public enum FilterCopy {
    /// The chip title of a filter.
    public static func title(_ filter: Filter) -> String {
        switch filter {
        case .all: "All"
        case .needsAttention: "Needs attention"
        case .updates: "Updates"
        case .notManaged: "Not managed"
        case .projectSkills: "Project skills"
        }
    }
}
