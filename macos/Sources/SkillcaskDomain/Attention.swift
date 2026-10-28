/// The sidebar badge: how many rows need a decision or a fix, and how many have updates (brief §8).
public struct Attention: Hashable, Sendable {
    public var errors = 0
    public var warnings = 0
    public var updates = 0

    public init(errors: Int = 0, warnings: Int = 0, updates: Int = 0) {
        self.errors = errors
        self.warnings = warnings
        self.updates = updates
    }

    public init(_ entries: [SkillEntry]) {
        for entry in entries {
            switch entry.health.severity {
            case .error: errors += 1
            case .warning: warnings += 1
            case .update: updates += 1
            case .ok, .neutral: break
            }
            if entry.health.severity != .update && entry.hasUpdate {
                updates += 1
            }
        }
    }

    /// Rows that are red or amber; the badge count.
    public var needing: Int {
        errors + warnings
    }

    /// The badge colour: the worst thing present, nil when everything is fine.
    public var worst: Severity? {
        if errors > 0 { return .error }
        if warnings > 0 { return .warning }
        if updates > 0 { return .update }
        return nil
    }
}
