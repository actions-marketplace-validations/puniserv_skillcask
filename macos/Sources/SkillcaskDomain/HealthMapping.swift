import SkillcaskCore

/// The one place that turns CLI facts into a `Health`. Pure, table-tested.
public enum HealthMapping {
    /// Worst thing first: the entry's own state, then audit findings, then a pending update, then a cooldown.
    public static func health(state: SkillState, update: Update?, findings: [AuditDocument.Finding]) -> Health {
        switch state {
        case .notInstalled: return .notInstalled
        case .modified: return .changedOnDisk
        case .notInLock, .notInManifest: return .needsSync(reason: stateText(state))
        case .drift(let reason): return .needsSync(reason: reason)
        case .duplicate(let text): return .duplicate(text)
        case .other(let text): return .unknown(text)
        case .ok, .project, .handWritten, .notManaged, .notLinked: break
        }
        if findings.contains(where: \.isModified) {
            return .changedOnDisk
        }
        if !findings.isEmpty {
            return .findings(findings.count)
        }
        switch state {
        case .notManaged: return .notManaged
        case .notLinked: return .notLinked
        default: break
        }
        if let (from, to) = update?.available {
            return .updateAvailable(from: from, to: to)
        }
        if let update, update.cooldown != nil {
            return .cooldown(until: update.note)
        }
        switch state {
        case .project: return .projectSkill
        case .handWritten: return .localSkill
        default: return .installed
        }
    }

    /// The health a detail header states (S3 note "dot+label from status.state"): the state and the update only,
    /// audit findings left out (they show in the Overview's Security row and on the list row), except a `modified`
    /// finding, which is a state ("Changed on disk").
    public static func stateHealth(state: SkillState, update: Update?, findings: [AuditDocument.Finding]) -> Health {
        health(state: state, update: update, findings: findings.filter(\.isModified))
    }

    static func stateText(_ state: SkillState) -> String {
        switch state {
        case .notInLock: "not in skills.lock"
        case .notInManifest: "not in skills.toml"
        default: ""
        }
    }

    public static func kind(of entry: StatusDocument.Entry) -> SkillEntry.Kind {
        switch (entry.package, entry.skill) {
        case (let package?, _?) where !entry.via.isEmpty: .dependency(package, via: entry.via)
        case (let package?, _?): .package(package)
        case (let package?, nil): .packageOnly(package)
        case (nil, _):
            switch SkillState(cliState: entry.state) {
            case .project, .notLinked: .project
            case .handWritten: .handWritten
            default: .notManaged(adopt: entry.adopt)
            }
        }
    }
}
