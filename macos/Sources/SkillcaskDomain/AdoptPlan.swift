import SkillcaskCore

/// What the Adopt sheet (S9) can do with the skills it was asked for, as a pure value.
///
/// Adopt is `skillcask -g add --adopt -- <spec>` (D38): `src/commands.rs` `adopt` refuses any scope but the
/// personal one ("--adopt applies only with --global"), so in a project `isAvailable` is false and `command`
/// builds nothing. On 0.9.1 `status` reports not managed rows only for `-g` (`not_managed` returns nothing for a
/// project), so a project row reaches the sheet only from a newer CLI or the design fixtures; the sheet then says
/// why it cannot adopt rather than offer a button that fails.
///
/// "Known source" is a not managed row whose `status.adopt` spec the CLI printed (from the `npx skills` lock); a
/// row without one needs a source typed in (`PackageSpec.validate`).
public struct AdoptPlan: Hashable, Sendable {
    /// One requested skill that is still not managed.
    public struct Item: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        /// The `status.adopt` spec; nil when the source is unknown.
        public let spec: String?
        /// The version of the copy on disk, as `status` reports it; nil when unknown.
        public let version: String?

        public init(id: String, name: String, spec: String?, version: String?) {
            self.id = id
            self.name = name
            self.spec = spec
            self.version = version
        }

        public var hasSource: Bool {
            spec != nil
        }
    }

    /// The requested skills that the snapshot lists as not managed, in request order; a skill that is gone or
    /// already managed is left out.
    public let items: [Item]
    /// The scope is the personal one, the only one the CLI adopts in.
    public let isAvailable: Bool

    public init(skills: [String], entries: [SkillEntry], scope: Scope) {
        items = skills.compactMap { id in
            guard let entry = entries.first(where: { $0.id == id }), case .notManaged(let adopt) = entry.kind else {
                return nil
            }
            let spec = adopt.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            return Item(id: entry.id, name: entry.name, spec: spec, version: entry.version)
        }
        isAvailable = scope.isPersonal
    }

    /// Several skills: the checklist (Adopt-States "Batch").
    public var isBatch: Bool {
        items.count > 1
    }

    /// The items with a recorded source, selectable in the batch.
    public var known: [Item] {
        items.filter(\.hasSource)
    }

    /// The items that need a source first (disabled in the batch).
    public var unknown: [Item] {
        items.filter { !$0.hasSource }
    }

    /// Adopt All with Known Sources… (Adopt-States "Batch", from the Not managed rows): every not managed row in
    /// list order, so the checklist also shows the ones that need a source; nil when none has a recorded source.
    public static func batchSkills(_ entries: [SkillEntry]) -> [String]? {
        let rows = entries.filter(\.isNotManaged)
        guard rows.contains(where: { if case .notManaged(_?) = $0.kind { true } else { false } }) else { return nil }
        return rows.map(\.id)
    }

    /// `add --adopt -- <spec>` in `scope`, or nil when `scope` is a project (the CLI refuses it) or `spec` is empty.
    public static func command(spec: String, scope: Scope) -> Invocation.Command? {
        let spec = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scope.isPersonal, !spec.isEmpty else { return nil }
        return .add(spec: spec, repository: nil, adopt: true, rename: [:], skills: [])
    }
}
