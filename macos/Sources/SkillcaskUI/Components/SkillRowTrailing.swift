import SkillcaskDomain

/// What the trailing slot of a skill row shows: exactly one thing, by the S2 note ("→ within" for an update,
/// "N findings", else the state label from the vocabulary) plus the boards' neutral `Dependency` for a healthy
/// row another package pulls in. Pure: `resolve` reads a `SkillEntry` and whether the app is offline.
public enum SkillRowTrailing: Hashable, Sendable {
    /// `→ 1.4.0` in mono and the update colour: the row's health is an available update and the app is online.
    case update(to: String)
    /// `2 findings` behind the warning glyph: the row's health is its audit findings.
    case findings(Int)
    /// `Dependency`, neutral dot and text: a healthy row pulled in by another package (Main, Components boards).
    case dependency
    /// The state label of every other row, worded by `Labels.health`.
    case state(Health)

    /// The S2 rule. Offline, the two states that only `outdated` knows (an update, a cooldown) fall back to what
    /// the lock knows ("update badges and → x.y.z hidden, lock-known states stay"); findings and every other state
    /// come from local files and stay.
    public static func resolve(_ entry: SkillEntry, offline: Bool = false) -> SkillRowTrailing {
        switch entry.health {
        case .updateAvailable(_, let to):
            return offline ? lockKnown(entry) : .update(to: to)
        case .cooldown:
            return offline ? lockKnown(entry) : .state(entry.health)
        case .findings(let count):
            return .findings(count)
        case .installed:
            return lockKnown(entry)
        default:
            return .state(entry.health)
        }
    }

    /// A healthy row: `Dependency` when another package requires it, else `Installed`.
    private static func lockKnown(_ entry: SkillEntry) -> SkillRowTrailing {
        if case .dependency = entry.kind {
            return .dependency
        }
        return .state(.installed)
    }

    /// The colour of the slot and of the row's dot.
    public var severity: Severity {
        switch self {
        case .update: .update
        case .findings: .warning
        case .dependency: .neutral
        case .state(let health): health.severity
        }
    }

    /// The slot's words.
    public var label: String {
        switch self {
        case .update(let to): RowCopy.arrow(to: to)
        case .findings(let count): Labels.findings(count)
        case .dependency: RowCopy.dependency
        case .state(let health): Labels.health(health)
        }
    }

    /// Quiet rows (ok, neutral: `Installed`, `Project skill`, `Dependency`) draw the label regular in
    /// `Color.textSecondary`; everything else medium in the status text colour, as the boards draw them.
    public var isQuiet: Bool {
        severity <= .ok
    }
}
