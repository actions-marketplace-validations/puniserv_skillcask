/// A JSON value of unknown shape, for keys whose type varies per entry (policy values are bools, strings or lists).
public enum JSONValue: Hashable, Sendable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// The value as the CLI would print it in text mode: `true`, `72h`, `packagist, github`.
    public var shown: String {
        switch self {
        case .null: "none"
        case .bool(let bool): bool ? "true" : "false"
        case .number(let number): number == number.rounded() ? String(Int(number)) : String(number)
        case .string(let string): string
        case .array(let items): items.map(\.shown).joined(separator: ", ")
        case .object(let fields):
            fields.keys.sorted().map { "\($0)=\(fields[$0, default: .null].shown)" }.joined(separator: ", ")
        }
    }
}
