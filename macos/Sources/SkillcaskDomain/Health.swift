/// The five colours of the status dot. Ordered so `max` is the worst.
public enum Severity: Int, Comparable, Hashable, Sendable, CaseIterable {
    case neutral
    case ok
    case update
    case warning
    case error

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What one row says about itself, worst thing first. The UI maps each case to a label; no copy lives here.
public enum Health: Hashable, Sendable {
    case installed
    case projectSkill
    case localSkill
    case updateAvailable(from: String, to: String)
    case notManaged
    case notLinked
    case findings(Int)
    case cooldown(until: String?)
    case notInstalled
    case changedOnDisk
    case needsSync(reason: String)
    case duplicate(String)
    case unknown(String)

    public var severity: Severity {
        switch self {
        case .installed, .projectSkill, .localSkill: .ok
        case .updateAvailable: .update
        case .notManaged, .notLinked, .findings, .cooldown, .unknown: .warning
        case .notInstalled, .changedOnDisk, .needsSync, .duplicate: .error
        }
    }
}
