/// `config --json -- <key>` (D48, 0.9.4): one setting's effective value and the layer it came from. Both are
/// `null` (and the CLI exits 1) when nothing sets the key.
public struct ConfigValueDocument: Decodable, Hashable, Sendable {
    /// `true`/`false`, a string, a number or a list, as the key has it; `.null` when not set.
    public let value: JSONValue
    /// `config.toml`, `config.toml, enforced`, `skills.toml`, `environment` or `default`; nil when not set.
    public let from: String?

    enum CodingKeys: String, CodingKey {
        case value
        case from
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decodeIfPresent(JSONValue.self, forKey: .value) ?? .null
        from = try c.decodeIfPresent(String.self, forKey: .from)
    }
}
