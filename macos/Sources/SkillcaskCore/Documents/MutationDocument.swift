/// Planned (`Capabilities.Feature.jsonMutations`): the result `init`, `install`, `update`, `add` and `remove` will
/// print with `--json`. Until the CLI ships it, mutations are judged by their exit code and the targeted refresh
/// that follows. Every key is optional so a first release with fewer keys still decodes.
public struct MutationDocument: Decodable, Hashable, Sendable {
    public let ok: Bool
    public let added: [String]
    public let installed: [String]
    public let updated: [String]
    public let removed: [String]
    public let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case ok
        case added
        case installed
        case updated
        case removed
        case warnings
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        added = try c.decodeIfPresent([String].self, forKey: .added) ?? []
        installed = try c.decodeIfPresent([String].self, forKey: .installed) ?? []
        updated = try c.decodeIfPresent([String].self, forKey: .updated) ?? []
        removed = try c.decodeIfPresent([String].self, forKey: .removed) ?? []
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}
