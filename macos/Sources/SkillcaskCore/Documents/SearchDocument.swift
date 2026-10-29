/// `search --json` (D32, D42): results from the allowed repositories, Packagist last, and skills.sh when enabled.
public struct SearchDocument: Decodable, Hashable, Sendable {
    public struct Result: Decodable, Hashable, Sendable {
        public let name: String
        public let description: String?
        /// The repository name, `packagist`, or `skills.sh`.
        public let source: String?
        /// skills.sh install count; nil elsewhere.
        public let installs: Int?
    }

    /// Whether skills.sh was searched, and whether the user has ever decided (`[search] skills-sh` in config.toml).
    public enum SkillsSh: Hashable, Sendable {
        /// The key was `null`: the CLI asks; the app shows the consent card.
        case undecided
        case enabled
        case disabled
        /// The CLI printed no key (before 0.9.0).
        case unknown
    }

    public let results: [Result]
    public let skillsSh: SkillsSh

    enum CodingKeys: String, CodingKey {
        case results
        case skillsSh = "skills-sh"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = try c.decode([Result].self, forKey: .results)
        if !c.contains(.skillsSh) {
            skillsSh = .unknown
        } else if try c.decodeNil(forKey: .skillsSh) {
            skillsSh = .undecided
        } else {
            skillsSh = try c.decode(Bool.self, forKey: .skillsSh) ? .enabled : .disabled
        }
    }
}
