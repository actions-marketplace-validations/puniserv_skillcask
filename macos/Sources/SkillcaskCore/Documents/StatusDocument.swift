/// `status --json` (D32): every skill the scope knows about, the effective policy, the agent targets and the
/// repositories. Exit 1 with this document when any entry is unhealthy. Keys are only ever added, so unknown keys
/// are ignored and later keys are optional.
public struct StatusDocument: Decodable, Hashable, Sendable {
    public struct Entry: Decodable, Hashable, Sendable {
        /// The package name alone; nil for a project, hand-written or not managed skill.
        public let package: String?
        /// The packages that require this one when it is a dependency rather than a manifest entry. Until
        /// `Capabilities.Feature.statusVia`, parsed from the `name (via a, b)` label the CLI prints.
        public let via: [String]
        public let version: String?
        public let skill: String?
        /// The CLI's state word (`ok`, `modified`, `not installed`, `project`, `not managed`, …) or a drift sentence.
        public let state: String
        public let ok: Bool
        /// For a `not managed` personal skill: the `add --adopt` source recorded by `npx skills` (D38).
        public let adopt: String?
        /// Planned (`statusDescription`): the skill's front-matter description.
        public let description: String?

        enum CodingKeys: String, CodingKey {
            case package
            case via
            case version
            case skill
            case state
            case ok
            case adopt
            case description
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let label = try c.decodeIfPresent(String.self, forKey: .package)
            let split = label.map(Self.splitVia)
            package = split?.name
            via = try c.decodeIfPresent([String].self, forKey: .via) ?? split?.via ?? []
            version = try c.decodeIfPresent(String.self, forKey: .version)
            skill = try c.decodeIfPresent(String.self, forKey: .skill)
            state = try c.decode(String.self, forKey: .state)
            ok = try c.decode(Bool.self, forKey: .ok)
            adopt = try c.decodeIfPresent(String.self, forKey: .adopt)
            description = try c.decodeIfPresent(String.self, forKey: .description)
        }

        /// `acme/dep (via acme/one, acme/two)` → (`acme/dep`, [`acme/one`, `acme/two`]).
        static func splitVia(_ label: String) -> (name: String, via: [String]) {
            guard label.hasSuffix(")"), let range = label.range(of: " (via ") else { return (label, []) }
            let list = label[range.upperBound..<label.index(before: label.endIndex)]
            return (String(label[..<range.lowerBound]), list.split(separator: ", ").map(String.init))
        }
    }

    /// One effective policy key with where it came from (`skills.toml`, `config.toml`, `env`, `default`).
    public struct Policy: Decodable, Hashable, Sendable {
        public let value: JSONValue
        public let from: String
    }

    public struct Targets: Decodable, Hashable, Sendable {
        public let entries: [String]
        public let dirs: [String]
        /// `skills.toml`, `config.toml` or `default`.
        public let from: String?
    }

    /// Since 0.9.0 (D42): every source the scope may resolve in.
    public struct Repository: Decodable, Hashable, Sendable {
        public let name: String
        public let type: String
        public let url: String
        public let allowed: Bool
    }

    public let ok: Bool
    public let entries: [Entry]
    public let policy: [String: Policy]
    public let targets: Targets?
    public let repositories: [Repository]

    enum CodingKeys: String, CodingKey {
        case ok
        case entries
        case policy
        case targets
        case repositories
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decode(Bool.self, forKey: .ok)
        entries = try c.decode([Entry].self, forKey: .entries)
        policy = try c.decodeIfPresent([String: Policy].self, forKey: .policy) ?? [:]
        targets = try c.decodeIfPresent(Targets.self, forKey: .targets)
        repositories = try c.decodeIfPresent([Repository].self, forKey: .repositories) ?? []
    }
}
