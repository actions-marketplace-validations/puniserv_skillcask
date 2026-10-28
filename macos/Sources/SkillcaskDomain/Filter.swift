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

    /// Entries matching the chip and the query (name, package or description, case-insensitive), in `sort` order
    /// (worst first, then by name, unless the list's sort menu says otherwise).
    public func apply(_ entries: [SkillEntry], query: String = "", sort: SortOrder = .state) -> [SkillEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return sort.apply(entries.filter { matches($0) && (needle.isEmpty || $0.searchText.contains(needle)) })
    }
}

extension SkillEntry {
    var searchText: String {
        [name, package ?? "", description ?? ""].joined(separator: " ").lowercased()
    }
}
