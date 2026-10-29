/// `audit --json` (D32): per installed skill, what its files reach for and the findings against the policy.
/// Exit 1 with this document when any skill has findings.
public struct AuditDocument: Decodable, Hashable, Sendable {
    public struct Finding: Decodable, Hashable, Sendable {
        /// `risky-pattern`, `modified`, `source`, … (`src/commands.rs` AUDIT_RULES).
        public let rule: String
        public let path: String
        public let line: Int?
        public let message: String
    }

    public struct Skill: Decodable, Hashable, Sendable {
        public let skill: String
        /// `package`, `project`, `hand-written` or `not managed`.
        public let kind: String
        /// Relative to the project, or to the home directory with `-g`.
        public let path: String
        public let package: String?
        public let version: String?
        public let findings: [Finding]
        public let commands: [String]
        public let network: [String]
        public let paths: [String]
        public let env: [String]
        public let scripts: [String]
    }

    public let ok: Bool
    public let skills: [Skill]
}
