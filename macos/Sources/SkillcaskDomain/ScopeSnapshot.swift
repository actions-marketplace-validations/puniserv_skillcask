import Foundation
import SkillcaskCore

/// Everything the main window shows for one scope, built from the documents of one refresh. `outdated` is
/// optional because updates are only known after an explicit check.
public struct ScopeSnapshot: Hashable, Sendable {
    public struct PolicyRow: Hashable, Sendable, Identifiable {
        public let key: String
        public let value: String
        public let from: String

        public var id: String {
            key
        }
    }

    public struct Doctor: Hashable, Sendable {
        public let ok: Bool
        public let passed: [String]
        public let problems: [String]
        public let fixed: [String]
        public let warnings: [String]
    }

    public let entries: [SkillEntry]
    public let attention: Attention
    public let policy: [PolicyRow]
    public let targets: StatusDocument.Targets?
    public let repositories: [StatusDocument.Repository]
    public let doctor: Doctor?
    /// Packages `outdated` lists as behind their constraint's newest; nil until updates were checked.
    public let updates: [Update]?
    public let checkedAt: Date

    public init(
        status: StatusDocument, audit: AuditDocument?, doctor: DoctorDocument?, outdated: OutdatedDocument?,
        checkedAt: Date = Date()
    ) {
        let updates = outdated.map {
            Dictionary($0.packages.map { ($0.package, Update($0)) }, uniquingKeysWith: { first, _ in first })
        }
        let audited = Dictionary((audit?.skills ?? []).map { ($0.skill, $0) }, uniquingKeysWith: { first, _ in first })
        entries = status.entries.map { entry in
            let state = SkillState(cliState: entry.state)
            let kind = HealthMapping.kind(of: entry)
            let name = entry.skill ?? entry.package ?? entry.state
            let skill = entry.skill.flatMap { audited[$0] }
            let findings = skill?.findings ?? []
            let update = entry.package.flatMap { updates?[$0] }
            return SkillEntry(
                id: name, name: name, kind: kind, version: entry.version, state: state,
                health: HealthMapping.health(state: state, update: update, findings: findings), update: update,
                findings: findings, path: skill?.path, description: entry.description)
        }
        attention = Attention(entries)
        policy = status.policy.keys.sorted()
            .map {
                PolicyRow(key: $0, value: status.policy[$0]?.value.shown ?? "", from: status.policy[$0]?.from ?? "")
            }
        targets = status.targets
        repositories = status.repositories
        self.doctor = doctor.map {
            Doctor(ok: $0.ok, passed: $0.passed, problems: $0.problems, fixed: $0.fixed, warnings: $0.warnings)
        }
        self.updates = updates.map { Array($0.values).sorted { $0.package < $1.package } }
        self.checkedAt = checkedAt
    }

    public var updatesChecked: Bool {
        updates != nil
    }

    /// Updates `update` would apply, one per package.
    public var availableUpdates: [Update] {
        (updates ?? []).filter { $0.available != nil }
    }

    public func entry(id: SkillEntry.ID?) -> SkillEntry? {
        id.flatMap { id in entries.first { $0.id == id } }
    }
}
