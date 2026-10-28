import Foundation

/// The CLI's `config.toml`, read as data (never written: only the CLI writes it). The app needs one value from it,
/// `[search] skills-sh`, because no command prints it without running a search; `search --skills-sh|--no-skills-sh
/// --remember` is how the app changes it.
public enum CLIConfig {
    /// `<config dir>/config.toml`, in the directory `Scope.configDirectory` resolves from the child's environment.
    public static func file(environment: [String: String], home: URL) -> URL {
        Scope.configDirectory(environment: environment, home: home).appending(path: "config.toml")
    }

    /// `[search] skills-sh` of `text`: true or false when the file sets it, nil when it does not (never decided) or
    /// writes it in a shape this reader does not follow (an inline `search = { … }` table). Reads a `[search]` or
    /// `["search"]` table and a top-level dotted `search.skills-sh` key, as `toml_edit` writes and people type them,
    /// and skips the inside of multi-line strings.
    public static func skillsSh(in text: String) -> Bool? {
        var table: String?
        var found: Bool?
        /// The delimiter of the multi-line string being skipped, while inside one.
        var multiline: String?
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let raw = String(raw)
            if let open = multiline {
                if raw.contains(open) {
                    multiline = nil
                }
                continue
            }
            multiline = Self.multilineDelimiters.first { raw.components(separatedBy: $0).count % 2 == 0 }
            let line = Self.uncommented(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }
            if line.hasPrefix("[") {
                table = Self.key(line.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t")))
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = Self.key(String(line[..<equals]))
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            let path = (table.map { $0 + "." } ?? "") + key
            if path == "search.skills-sh", let flag = Bool(value) {
                found = flag
            }
        }
        return found
    }

    /// TOML's multi-line string delimiters: a line with an odd number of one opens (or closes) such a string.
    private static let multilineDelimiters = [String(repeating: "\"", count: 3), String(repeating: "'", count: 3)]

    /// `"skills-sh"` and `skills-sh` name the same key; a dotted key keeps its dots.
    private static func key(_ text: String) -> String {
        text.split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .joined(separator: ".")
    }

    /// The line before a `#` outside quotes.
    private static func uncommented(_ line: String) -> String {
        var quote: Character?
        for index in line.indices {
            let character = line[index]
            if let open = quote {
                if character == open {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                return String(line[..<index])
            }
        }
        return line
    }
}
