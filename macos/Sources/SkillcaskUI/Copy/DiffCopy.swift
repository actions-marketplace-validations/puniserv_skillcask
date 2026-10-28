import SkillcaskDomain

/// The words of the diff pane (Components "Diff viewer", ReviewUpdate): the `+14 −3` counts, the file-list words
/// for files without counts, the flag pills and the way an escaped invisible character is shown.
public enum DiffCopy {
    /// The real minus sign of the board's `−3`, not a hyphen.
    public static let minus = "−"

    /// `+14 −3`; `+17` or `−6` when one side is zero; empty when both are.
    public static func counts(additions: Int, deletions: Int) -> String {
        [additions > 0 ? added(additions) : nil, deletions > 0 ? removed(deletions) : nil].compactMap { $0 }
            .joined(separator: " ")
    }

    /// `+14`.
    public static func added(_ count: Int) -> String {
        "+\(count)"
    }

    /// `−3`.
    public static func removed(_ count: Int) -> String {
        "\(minus)\(count)"
    }

    /// The file list's word after a path that has no counts to show, as the boards write them: `new`, `removed`,
    /// `binary`; the CLI's two other shapes get a word in the same voice. Nil when the file has text counts.
    public static func word(for change: UnifiedDiff.File.Change) -> String? {
        switch change {
        case .added: "new"
        case .removed: "removed"
        case .binary: "binary"
        case .tooLarge: "too large"
        case .modeOnly: "mode only"
        case .modified: nil
        }
    }

    /// The note row drawn instead of lines for a file the CLI did not print. No board draws this row (the boards
    /// only list a binary file with the word `binary`), so the wording is this file's, in the boards' voice.
    public static func note(for change: UnifiedDiff.File.Change) -> String? {
        switch change {
        case .binary: "Binary file"
        case .tooLarge: "Too large to show"
        case .modeOnly: "Only the file mode changed"
        case .added, .removed, .modified: nil
        }
    }

    /// What assistive technology hears before an added or removed line; context lines read as their text.
    public static let addedLine = "Added line"
    public static let removedLine = "Removed line"

    /// The pill after a flagged line: `risky pattern`, `invisible character`.
    public static func flag(_ kind: DiffFlag.Kind) -> String {
        switch kind {
        case .risky: "risky pattern"
        case .invisible: "invisible character"
        }
    }

    /// The CLI escapes control and invisible characters as `<U+202E>` (D26); the boards show them as
    /// `‹U+202E›`, single angle quotation marks around the code point, so the escape cannot be mistaken for
    /// markup the file itself contains. Only the exact `<U+XXXX>` shape (four to six hex digits) is rewritten.
    public static func shown(_ text: String) -> String {
        guard text.contains("<U+") else { return text }
        var out = ""
        var rest = Substring(text)
        while let start = rest.range(of: "<U+") {
            out += rest[..<start.lowerBound]
            let after = rest[start.upperBound...]
            let hex = after.prefix { $0.isHexDigit }
            let end = after.index(after.startIndex, offsetBy: hex.count)
            if (4...6).contains(hex.count), end < after.endIndex, after[end] == ">" {
                out += "‹U+\(hex)›"
                rest = after[after.index(after: end)...]
            } else {
                out += "<U+"
                rest = after
            }
        }
        out += rest
        return out
    }
}
