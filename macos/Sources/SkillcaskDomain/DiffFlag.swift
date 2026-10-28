import SkillcaskCore

/// A line of the new version that an audit finding points at, so the review sheet can outline it: amber for a
/// risky pattern, iris for an invisible character (designer note S7). `line` is the number in the new version,
/// the same count the gutter's right column shows.
public struct DiffFlag: Hashable, Sendable {
    public enum Kind: Hashable, Sendable, CaseIterable {
        /// Audit rule `risky-pattern`.
        case risky
        /// Audit rule `invisible-character`.
        case invisible
    }

    public let line: Int
    public let kind: Kind

    public init(line: Int, kind: Kind) {
        self.line = line
        self.kind = kind
    }

    /// The flags of `file`: every finding whose `path` ends with the file's path (audit paths are relative to the
    /// project, diff paths to the package root), whose rule is one of the two flagged kinds and whose `line`
    /// exists in the new version of the file. In file order of the findings, one flag per line; when two findings
    /// name the same line the risky one wins, since it is the worse of the two.
    public static func flags(for file: UnifiedDiff.File, findings: [AuditDocument.Finding]) -> [DiffFlag] {
        let newLines = Set(file.diffLines.compactMap(\.newNumber))
        var flags: [Int: Kind] = [:]
        var order: [Int] = []
        for finding in findings {
            guard let kind = Kind(rule: finding.rule), let line = finding.line, newLines.contains(line),
                finding.path.hasSuffix(file.path)
            else { continue }
            if let existing = flags[line] {
                if existing == .invisible, kind == .risky {
                    flags[line] = .risky
                }
            } else {
                flags[line] = kind
                order.append(line)
            }
        }
        return order.compactMap { line in flags[line].map { DiffFlag(line: line, kind: $0) } }
    }
}

extension DiffFlag.Kind {
    /// The two `FindingKind`s the sheet outlines; any other rule is nil.
    public init?(rule: String) {
        switch FindingKind(rule: rule) {
        case .riskyPattern: self = .risky
        case .invisibleCharacter: self = .invisible
        case .modified, .other: return nil
        }
    }
}
