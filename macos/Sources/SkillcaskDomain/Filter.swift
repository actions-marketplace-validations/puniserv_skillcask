/// The filter chips above the list (brief IA). `apply` also takes the search field's text.
public enum Filter: String, CaseIterable, Hashable, Sendable {
    case all
    case needsAttention
    case updates
    case notManaged
    case projectSkills

    public func matches(_ entry: SkillEntry) -> Bool {
        switch self {
        case .all: true
        case .needsAttention: entry.health.severity >= .warning
        case .updates: entry.hasUpdate
        case .notManaged: entry.isNotManaged
        case .projectSkills: entry.isProjectSkill || entry.kind == .handWritten
        }
    }

    /// Entries matching the chip and the query (name, package or description, case-insensitive), worst first,
    /// then by name.
    public func apply(_ entries: [SkillEntry], query: String = "") -> [SkillEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return
            entries
            .filter { matches($0) && (needle.isEmpty || $0.searchText.contains(needle)) }
            .sorted { lhs, rhs in
                if lhs.health.severity != rhs.health.severity {
                    return lhs.health.severity > rhs.health.severity
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}

extension SkillEntry {
    var searchText: String {
        [name, package ?? "", description ?? ""].joined(separator: " ").lowercased()
    }
}
