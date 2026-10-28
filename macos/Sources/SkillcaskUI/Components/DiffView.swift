import SkillcaskDomain
import SwiftUI

/// The diff pane of the review sheet (ReviewUpdate board, right of the file list): a `DiffFileHeader` strip,
/// then the file's rows as `DiffLineView`s on the window surface with the board's 4 pt above and below. Lines
/// come numbered from Domain (`UnifiedDiff.File.diffLines`); flags are matched by their new-version number.
/// Without `wrapsLines` the rows scroll sideways as one block; with it long lines wrap in place. A binary or
/// too-large file shows one note row in the CLI's place. A flagged row wraps even when the pane does not, at the
/// pane's width, so its pill and outline never leave the viewport.
public struct DiffView: View {
    /// The board's `padding: 4px 0` around the rows.
    nonisolated static let rowsPaddingV = Spacing.xs

    public let file: UnifiedDiff.File
    public let flags: [DiffFlag]
    public let wrapsLines: Bool

    public init(_ file: UnifiedDiff.File, flags: [DiffFlag] = [], wrapsLines: Bool = false) {
        self.file = file
        self.flags = flags
        self.wrapsLines = wrapsLines
    }

    /// The rows to draw: the file's lines, or the note for a file the CLI did not print line by line.
    nonisolated public static func rows(for file: UnifiedDiff.File) -> [DiffLine] {
        if let note = DiffCopy.note(for: file.change) {
            return [DiffLine(id: 0, kind: .note, oldNumber: nil, newNumber: nil, text: note)]
        }
        return file.diffLines
    }

    /// The flag of each new-version line number. `DiffFlag.flags(for:findings:)` already yields one flag per line
    /// with risky ahead of invisible, so the first flag of a line is the one that counts.
    nonisolated public static func flagsByLine(_ flags: [DiffFlag]) -> [Int: DiffFlag.Kind] {
        Dictionary(flags.map { ($0.line, $0.kind) }, uniquingKeysWith: { first, _ in first })
    }

    public var body: some View {
        let rows = Self.rows(for: file)
        let byLine = Self.flagsByLine(flags)
        VStack(spacing: 0) {
            DiffFileHeader(file, flags: flags)
            GeometryReader { geometry in
                ScrollView(wrapsLines ? .vertical : [.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { line in
                            let flag = line.newNumber.flatMap { byLine[$0] }
                            DiffLineView(line, flag: flag, wrapsLines: wrapsLines)
                                .frame(width: flag == nil || wrapsLines ? nil : geometry.size.width)
                        }
                    }
                    .padding(.vertical, Self.rowsPaddingV)
                    .frame(minWidth: geometry.size.width, alignment: .leading)
                }
            }
        }
        .background(Color.surfaceWindow)
    }
}

#Preview("DiffView, light") {
    DiffViewSample()
}

#Preview("DiffView, dark") {
    DiffViewSample()
        .preferredColorScheme(.dark)
}

/// pdf's SKILL.md with the board's two flagged lines, at the sheet pane's width.
private struct DiffViewSample: View {
    var body: some View {
        if let file = DesignFixtures.pdfDiff.packages.first?.files.first {
            DiffView(file, flags: [DiffFlag(line: 12, kind: .risky), DiffFlag(line: 13, kind: .invisible)])
                .frame(width: 600, height: 480)
        }
    }
}
