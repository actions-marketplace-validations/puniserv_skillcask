import SkillcaskCore

/// The audit rules `src/commands.rs` AUDIT_RULES prints, typed, so no view compares a rule string. `modified`
/// is not a finding about the text (the folder differs from the lock) and is counted as "changed on disk";
/// the other two are what the Security card, tab and the review sheet show. Unknown rules of a newer CLI
/// survive as `.other`.
public enum FindingKind: Hashable, Sendable {
    /// Rule `modified`: the installed folder differs from what the lock recorded.
    case modified
    /// Rule `risky-pattern`: a line asks an agent to run or download something.
    case riskyPattern
    /// Rule `invisible-character`: a control, bidi or zero-width character.
    case invisibleCharacter
    case other(String)

    public init(rule: String) {
        switch rule {
        case "modified": self = .modified
        case "risky-pattern": self = .riskyPattern
        case "invisible-character": self = .invisibleCharacter
        default: self = .other(rule)
        }
    }

    /// A finding about the skill's text, as opposed to the folder differing from the lock.
    public var isTextFinding: Bool {
        self != .modified
    }
}

extension AuditDocument.Finding {
    /// The rule, typed.
    public var kind: FindingKind {
        FindingKind(rule: rule)
    }

    /// The folder differs from the lock (rule `modified`).
    public var isModified: Bool {
        kind == .modified
    }
}
