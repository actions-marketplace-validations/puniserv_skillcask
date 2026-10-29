import SkillcaskCore
import SkillcaskDomain

/// What the Contents tab shows for the selected row (Contents, Contents-States): the rendered file, the "too
/// large" message (the 256 KiB cap of D41: nothing is rendered), the "can't read" message, or nothing yet while
/// the detail loads.
enum ContentsState: Equatable {
    case loading
    /// The front matter and the body, with the warning strip when the audit found invisible characters.
    case normal(SkillText, warnsInvisible: Bool)
    case tooLarge
    case unreadable

    /// The state for `entry` given the loaded `detail`: a truncated text is too large, a missing text with a
    /// read error (or a row without a path) is unreadable.
    static func resolve(entry: SkillEntry, detail: SkillDetail?, isLoading: Bool) -> ContentsState {
        guard let detail else { return isLoading || entry.path != nil ? .loading : .unreadable }
        guard let text = detail.text else { return .unreadable }
        if text.truncated {
            return .tooLarge
        }
        return .normal(text, warnsInvisible: warnsInvisible(entry))
    }

    /// The S4 rule: the strip shows when the audit has an `invisible-character` finding for the skill.
    static func warnsInvisible(_ entry: SkillEntry) -> Bool {
        entry.findings.contains { $0.kind == .invisibleCharacter }
    }

    /// The rendered block holding file line `line` (an audit finding's or Security's "Show in file"), via the
    /// body's first file line; nil for a line in the front matter, on a blank line or past the end.
    static func blockIndex(forFileLine line: Int, text: SkillText, spans: [MarkdownBlocks.Span]) -> Int? {
        MarkdownBlocks.span(containing: line - text.bodyStartLine, in: spans)
    }

    /// The blocks to outline (Contents board, the diff pane's colours): every risky-pattern or invisible-character
    /// finding of this skill's SKILL.md with a line in the body, by block index; risky wins when both hit one block.
    static func flags(
        for entry: SkillEntry, text: SkillText, spans: [MarkdownBlocks.Span]
    ) -> [Int: DiffFlag.Kind] {
        let file = entry.path.map { $0 + "/" + ContentsFile.skillFileName } ?? ContentsFile.skillFileName
        var flags: [Int: DiffFlag.Kind] = [:]
        for finding in entry.findings {
            guard let kind = DiffFlag.Kind(rule: finding.rule), let line = finding.line, finding.path.hasSuffix(file),
                let index = blockIndex(forFileLine: line, text: text, spans: spans)
            else { continue }
            if flags[index] != .risky {
                flags[index] = kind
            }
        }
        return flags
    }

    /// Open in editor and Quick Look need a file to open; Copy path works whatever the state (Contents-States
    /// draws the two disabled on the unreadable file).
    var canOpenFile: Bool {
        self != .unreadable
    }
}
