import Foundation

/// A skill's SKILL.md as the app may show it: at most 256 KiB (D41), front matter split off, and every control or
/// invisible character made visible as `<U+XXXX>` (D26) so package text cannot reorder what the reader sees.
public struct SkillText: Hashable, Sendable {
    public static let maxBytes = 256 << 10

    /// `key: value` lines between the `---` fences, in file order, already escaped.
    public let frontMatter: [(key: String, value: String)]
    public let body: String
    public let truncated: Bool
    /// The 1-based line of the file where `body` starts: 1 without front matter, else the line after the closing
    /// `---`. An audit finding's `line` (a file line) is `bodyStartLine + n` for body line `n` (0-based).
    public let bodyStartLine: Int

    public init(
        frontMatter: [(key: String, value: String)], body: String, truncated: Bool, bodyStartLine: Int = 1
    ) {
        self.frontMatter = frontMatter
        self.body = body
        self.truncated = truncated
        self.bodyStartLine = bodyStartLine
    }

    /// Reads and escapes; the caller runs this off the main actor.
    public static func read(contentsOf url: URL) throws -> SkillText {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        return parse(String(decoding: data.prefix(maxBytes), as: UTF8.self), truncated: data.count > maxBytes)
    }

    public static func parse(_ text: String, truncated: Bool = false) -> SkillText {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { shown(String($0)) }
        var frontMatter: [(key: String, value: String)] = []
        var bodyStartLine = 1
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            for line in lines[1..<end] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    frontMatter.append((key, unquoted(value)))
                }
            }
            lines.removeSubrange(0...end)
            bodyStartLine = end + 2
        }
        return SkillText(
            frontMatter: frontMatter, body: lines.joined(separator: "\n"), truncated: truncated,
            bodyStartLine: bodyStartLine)
    }

    /// Control characters other than tab and newline, bidi controls, zero-width characters and Unicode tags as
    /// `<U+XXXX>`; the same set as the CLI's `shown` (`src/skill.rs`).
    public static func shown(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isInvisible) else { return text }
        var out = ""
        for scalar in text.unicodeScalars {
            if isInvisible(scalar) {
                out += String(format: "<U+%04X>", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A: false
        case 0x00...0x1F, 0x7F, 0x80...0x9F: true
        case 0x061C, 0x200B...0x200F, 0x202A...0x202E, 0x2060, 0x2066...0x2069, 0xFEFF, 0xE0000...0xE007F: true
        default: false
        }
    }

    /// YAML's double-quoted scalar: `"Team \"notes\""` → `Team "notes"`; single quotes likewise.
    static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first else {
            return value
        }
        let inner = String(value.dropFirst().dropLast())
        return first == "'"
            ? inner.replacingOccurrences(of: "''", with: "'") : inner.replacingOccurrences(of: "\\\"", with: "\"")
    }
}

extension SkillText {
    public static func == (lhs: SkillText, rhs: SkillText) -> Bool {
        lhs.body == rhs.body && lhs.truncated == rhs.truncated && lhs.bodyStartLine == rhs.bodyStartLine
            && lhs.frontMatter.map(\.key) == rhs.frontMatter.map(\.key)
            && lhs.frontMatter.map(\.value) == rhs.frontMatter.map(\.value)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(body)
        hasher.combine(truncated)
        hasher.combine(bodyStartLine)
        for (key, value) in frontMatter {
            hasher.combine(key)
            hasher.combine(value)
        }
    }
}
