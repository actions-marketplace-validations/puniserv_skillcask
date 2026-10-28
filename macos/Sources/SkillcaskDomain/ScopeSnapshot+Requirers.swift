extension ScopeSnapshot {
    /// The skills that pull a dependency in: the names of the entries whose package is in the `via` list of
    /// `entry.kind` (`.dependency(_, via:)`), sorted and without duplicates, so the detail header can say
    /// "Required by caveman" rather than name the package. A not managed row counts when its adopt spec names
    /// the package (`github:juliusbrussee/caveman` → `juliusbrussee/caveman`, the Main board's api scope).
    /// Empty for any other kind or when no entry of this snapshot belongs to a requiring package.
    public func requirerSkills(of entry: SkillEntry) -> [String] {
        guard case .dependency(_, let via) = entry.kind, !via.isEmpty else { return [] }
        let packages = Set(via)
        let names = entries.compactMap { candidate -> String? in
            guard candidate.id != entry.id, let package = Self.requiringPackage(of: candidate),
                packages.contains(package)
            else { return nil }
            return candidate.name
        }
        return Array(Set(names)).sorted()
    }

    /// The package a row stands for: its own, or the adopt spec of a not managed row without its `scheme:`.
    private static func requiringPackage(of entry: SkillEntry) -> String? {
        if let package = entry.package {
            return package
        }
        guard case .notManaged(let adopt?) = entry.kind else { return nil }
        guard let colon = adopt.firstIndex(of: ":") else { return adopt }
        let spec = adopt[adopt.index(after: colon)...]
        return spec.isEmpty ? nil : String(spec)
    }
}
