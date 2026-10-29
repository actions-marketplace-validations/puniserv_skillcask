import SkillcaskDomain
import SwiftUI

/// The diff pane of the review sheet (ReviewUpdate board, right of the file list): a `DiffFileHeader` strip,
/// then the file's rows as `DiffLineView`s on the window surface with the board's 4 pt above and below. Lines
/// come numbered from Domain (`UnifiedDiff.File.diffLines`); flags are matched by their new-version number.
/// Without `wrapsLines` the rows scroll sideways as one block; with it long lines wrap in place. A binary or
/// too-large file shows one note row in the CLI's place. A flagged row wraps even when the pane does not, at the
/// pane's width, so its pill and outline never leave the viewport. The review sheet's find outlines the matching
/// rows in the system accent (the current match 2 pt, the others 1 pt) and `scrollTarget` scrolls a row into view.
public struct DiffView: View {
    /// A row to bring into view; a new `serial` scrolls again to the same row.
    public struct ScrollTarget: Hashable, Sendable {
        public let line: DiffLine.ID
        public let serial: Int

        public init(line: DiffLine.ID, serial: Int) {
            self.line = line
            self.serial = serial
        }
    }

    /// The current find match's outline; the other matches take `Size.hairline`.
    nonisolated static let currentMatchOutline: CGFloat = 2

    /// The board's `padding: 4px 0` around the rows.
    nonisolated static let rowsPaddingV = Spacing.xs

    public let file: UnifiedDiff.File
    public let flags: [DiffFlag]
    public let wrapsLines: Bool
    /// Rows matching the find field.
    public let matches: Set<DiffLine.ID>
    public let currentMatch: DiffLine.ID?
    public let scrollTarget: ScrollTarget?

    public init(
        _ file: UnifiedDiff.File, flags: [DiffFlag] = [], wrapsLines: Bool = false, matches: Set<DiffLine.ID> = [],
        currentMatch: DiffLine.ID? = nil, scrollTarget: ScrollTarget? = nil
    ) {
        self.file = file
        self.flags = flags
        self.wrapsLines = wrapsLines
        self.matches = matches
        self.currentMatch = currentMatch
        self.scrollTarget = scrollTarget
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
                ScrollViewReader { proxy in
                    ScrollView(wrapsLines ? .vertical : [.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(rows) { line in
                                let flag = line.newNumber.flatMap { byLine[$0] }
                                DiffLineView(line, flag: flag, wrapsLines: wrapsLines)
                                    .frame(width: flag == nil || wrapsLines ? nil : geometry.size.width)
                                    .overlay {
                                        if matches.contains(line.id) {
                                            Rectangle()
                                                .strokeBorder(
                                                    Color.accentColor,
                                                    lineWidth: line.id == currentMatch
                                                        ? Self.currentMatchOutline : Size.hairline)
                                        }
                                    }
                                    .id(line.id)
                            }
                        }
                        .padding(.vertical, Self.rowsPaddingV)
                        .frame(minWidth: geometry.size.width, alignment: .leading)
                    }
                    .onChange(of: scrollTarget, initial: true) { _, target in
                        guard let target else { return }
                        proxy.scrollTo(target.line, anchor: .center)
                    }
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
