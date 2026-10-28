import SkillcaskDomain

/// Which controls the detail header shows for one row: the S3 rules of the designer's notes as a pure value.
///
/// "Update to X… only when within ≠ locked, else the text 'Up to date' sits in its place (no button). Remove…
/// always right, destructive style; hidden for dependency and project skills. Adopt… replaces Update for
/// not-managed rows. Package + source pill hidden for project/local skills." Offline, `outdated` has not
/// answered, so the slot reads "Updates unknown" (Detail-States) and the update strip stays hidden.
public struct DetailActions: Hashable, Sendable {
    /// What fills the primary slot: a button, or a quiet text where the button would be.
    public enum Primary: Hashable, Sendable {
        case update(to: String)
        case adopt
        case upToDate
        case updatesUnknown
    }

    public let primary: Primary?
    /// The project skill's note "Edit it in the repository" in the actions' place.
    public let showsEditNote: Bool
    public let showsRemove: Bool
    /// The blue strip under the tabs with "Review changes…".
    public let showsStrip: Bool
    public let showsSourcePill: Bool
    /// The mono path (`.skills/my-notes`, Detail-States) on the third line of a project or local skill, where a
    /// package row shows its package name; the "Project" pill stays hidden.
    public let showsPath: Bool

    public init(
        primary: Primary?, showsEditNote: Bool, showsRemove: Bool, showsStrip: Bool, showsSourcePill: Bool,
        showsPath: Bool
    ) {
        self.primary = primary
        self.showsEditNote = showsEditNote
        self.showsRemove = showsRemove
        self.showsStrip = showsStrip
        self.showsSourcePill = showsSourcePill
        self.showsPath = showsPath
    }

    /// The controls of `entry`; `offline` hides what needs `outdated`.
    public static func resolve(_ entry: SkillEntry, offline: Bool) -> DetailActions {
        let target = offline ? nil : updateTarget(of: entry)
        let primary: Primary?
        switch entry.kind {
        case .project, .handWritten:
            primary = nil
        case .notManaged:
            primary = .adopt
        case .package, .dependency, .packageOnly:
            if let target {
                primary = .update(to: target)
            } else if offline || entry.update == nil {
                primary = .updatesUnknown
            } else {
                primary = .upToDate
            }
        }
        let showsRemove: Bool
        switch entry.kind {
        case .package, .packageOnly, .notManaged: showsRemove = true
        case .dependency, .project, .handWritten: showsRemove = false
        }
        let showsSourcePill: Bool
        let showsPath: Bool
        switch entry.kind {
        case .project, .handWritten:
            showsSourcePill = false
            showsPath = true
        case .package, .dependency, .packageOnly, .notManaged:
            showsSourcePill = SourceKind.kind(of: entry) != nil
            showsPath = false
        }
        return DetailActions(
            primary: primary, showsEditNote: entry.isProjectSkill, showsRemove: showsRemove,
            showsStrip: target != nil, showsSourcePill: showsSourcePill, showsPath: showsPath)
    }

    /// The version an update would lock: from the row's `Health` when it carries one, else from `outdated`.
    public static func updateTarget(of entry: SkillEntry) -> String? {
        if case .updateAvailable(_, let to) = entry.health {
            return to
        }
        return entry.update?.available?.to
    }

    /// The mono text of the header's third line: the package name, or the adopt spec of a not managed row
    /// without its `github:` / `git:` prefix (`juliusbrussee/caveman` on Detail-States); nil when there is
    /// nothing to show.
    public static func packageText(of entry: SkillEntry) -> String? {
        if let package = entry.package {
            return package
        }
        guard case .notManaged(let adopt?) = entry.kind else { return nil }
        guard let colon = adopt.firstIndex(of: ":") else { return adopt }
        let spec = adopt[adopt.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return spec.isEmpty ? adopt : spec
    }
}
