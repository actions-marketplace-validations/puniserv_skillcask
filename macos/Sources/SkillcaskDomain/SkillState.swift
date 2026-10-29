/// The CLI's `state` word of a `status` entry, typed. Unknown words survive as `.other` so a newer CLI never
/// crashes an older app; they are shown as a warning with the CLI's text.
public enum SkillState: Hashable, Sendable {
    case ok
    case project
    case handWritten
    case notManaged
    case notLinked
    case notInstalled
    case modified
    case notInLock
    case notInManifest
    /// The manifest entry changed since the lock was written: `constraint changed from "^1" to "^2"`, …
    case drift(String)
    /// `skill "x" is provided by both a/b and c/d`.
    case duplicate(String)
    case other(String)

    public init(cliState text: String) {
        switch text {
        case "ok": self = .ok
        case "project": self = .project
        case "hand-written": self = .handWritten
        case "not managed": self = .notManaged
        case "not linked": self = .notLinked
        case "not installed": self = .notInstalled
        case "modified": self = .modified
        case "not in skills.lock": self = .notInLock
        case "not in skills.toml": self = .notInManifest
        case let t where t.hasPrefix("skill ") && t.contains(" is provided by both "): self = .duplicate(t)
        case let t where Self.driftPrefixes.contains(where: t.hasPrefix): self = .drift(t)
        default: self = .other(text)
        }
    }

    /// `src/commands.rs` `drift()`.
    static let driftPrefixes = [
        "constraint changed", "repository changed", "changed from ref", "changed from version",
        "skill selection changed",
        "rename changed",
    ]

    /// Mirrors the CLI's `healthy()`: these need no action from the user.
    public var isHealthy: Bool {
        switch self {
        case .ok, .project, .handWritten, .notManaged: true
        default: false
        }
    }
}
