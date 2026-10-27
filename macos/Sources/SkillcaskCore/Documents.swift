import Foundation

// The `--json` documents of D32. Keys are only ever added, so every type ignores unknown keys
// (Decodable's default) and optional keys stay optional.

public struct StatusDoc: Decodable, Sendable {
    public struct Entry: Decodable, Sendable, Hashable {
        public let package: String?
        public let version: String?
        public let skill: String?
        public let state: String
        public let ok: Bool
        /// For a `not managed` global skill: the `add --adopt` source `npx skills` recorded (D38).
        public let adopt: String?
    }
    public struct Targets: Decodable, Sendable {
        public let entries: [String]
        public let dirs: [String]
    }
    /// Since 0.9.0 (D42): every source the project may resolve in.
    public struct Repository: Decodable, Sendable, Hashable {
        public let name: String
        public let type: String
        public let url: String
        public let allowed: Bool
    }
    public let ok: Bool
    public let entries: [Entry]
    public let targets: Targets?
    public let repositories: [Repository]?
}

public struct OutdatedDoc: Decodable, Sendable {
    public struct Package: Decodable, Sendable {
        public let package: String
        public let locked: String?
        public let within: String?
        public let latest: String?
        public let note: String?
    }
    public let packages: [Package]
    public let behind: [String]
}

/// `info` of a package, or of a skill name (`skill`, `kind`, …); keys of the other shape are nil.
public struct InfoDoc: Decodable, Sendable {
    public struct Skill: Decodable, Sendable {
        public let name: String
        public let description: String?
    }
    /// `true` (no replacement) or the replacement package name.
    public struct Abandoned: Decodable, Sendable {
        public let replacement: String?
        public init(from decoder: Decoder) throws {
            replacement = try? decoder.singleValueContainer().decode(String.self)
        }
    }
    public let package: String?
    public let source: String?
    public let repository: String?
    public let version: String?
    public let locked: Bool?
    public let description: String?
    public let license: [String]?
    public let abandoned: Abandoned?
    public let versions: [String]?
    public let requires: [String: String]?
    public let skills: [Skill]?
    public let why: [String]?
    public let skill: String?
    public let kind: String?
    public let path: String?
    public let from: String?
}

public struct SearchDoc: Decodable, Sendable {
    public struct Result: Decodable, Sendable, Hashable {
        public let name: String
        public let description: String?
        /// Since 0.9.0: the repository name, or `skills.sh` (D42).
        public let source: String?
        public let installs: Int?
    }
    public let results: [Result]
    /// `"skills-sh": null` means the user never decided; 0.8.0 prints no key and has no flag to ask with.
    public let asksSkillsSh: Bool

    enum CodingKeys: String, CodingKey {
        case results
        case skillsSh = "skills-sh"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = try c.decode([Result].self, forKey: .results)
        asksSkillsSh = try c.contains(.skillsSh) && c.decodeNil(forKey: .skillsSh)
    }
}

public struct DoctorDoc: Decodable, Sendable {
    public let ok: Bool
    public let passed: [String]
    public let problems: [String]
    public let fixed: [String]
    public let warnings: [String]
}

/// `audit` exits 1 when it has findings and still prints this document.
public struct AuditDoc: Decodable, Sendable {
    public struct Finding: Decodable, Sendable, Hashable {
        public let rule: String
        public let path: String
        public let line: Int?
        public let message: String
    }
    public struct Skill: Decodable, Sendable {
        public let skill: String
        public let kind: String
        /// Relative to the project, or to the home directory with `-g`.
        public let path: String
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

/// `projects --json` (D40), CLI 0.9.0 and newer.
public struct ProjectsDoc: Decodable, Sendable {
    public struct Project: Decodable, Sendable {
        public let path: String
    }
    public let projects: [Project]
}
