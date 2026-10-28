import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// The diff pane over the pdf fixture (`ReviewUpdate` board): SKILL.md with its two flagged lines, the
    /// added `scripts/ocr.py`, the removed `LEGACY.md`, the binary `assets/sample.pdf`, SKILL.md wrapping at a
    /// narrow width, and the Components board's "Diff viewer" region with the file list beside the pane.
    static let diff: [Entry] = [
        Entry(id: "P2-9", state: "hunks", size: paneSize(for: pdfFile(0))) { AnyView(DiffPane(pdfFile(0))) },
        Entry(id: "P2-9", state: "added", size: paneSize(for: pdfFile(1))) { AnyView(DiffPane(pdfFile(1))) },
        Entry(id: "P2-9", state: "removed", size: paneSize(for: pdfFile(3))) { AnyView(DiffPane(pdfFile(3))) },
        Entry(id: "P2-9", state: "binary", size: paneSize(for: pdfFile(4))) { AnyView(DiffPane(pdfFile(4))) },
        Entry(id: "P2-9", state: "wrapped", size: CGSize(width: wrappedWidth, height: 420)) {
            AnyView(DiffPane(pdfFile(0), wrapsLines: true))
        },
        Entry(id: "P2-9", state: "files", size: CGSize(width: 640, height: 190)) { AnyView(DiffRegion()) },
    ]
}

/// The pane's width on the ReviewUpdate board (960 sheet minus the 230 file list and the chrome).
private let paneWidth: CGFloat = 600
/// Narrow enough that the pdf SKILL.md lines wrap.
private let wrappedWidth: CGFloat = 360
/// The strip above the rows: one caption line between the board's 6 pt paddings and the hairline.
private let headerHeight = Font.Token.Scale.monoSmall.lineHeight + 2 * DiffFileHeader.paddingV + Size.hairline

/// Tall enough for every row of `file` without a scroll.
private func paneSize(for file: UnifiedDiff.File) -> CGSize {
    let rows = CGFloat(DiffView.rows(for: file).count)
    return CGSize(width: paneWidth, height: headerHeight + 2 * DiffView.rowsPaddingV + rows * DiffLineView.height)
}

/// The pdf diff's files in order: SKILL.md, scripts/ocr.py, scripts/fill_form.py, LEGACY.md, assets/sample.pdf.
private func pdfFile(_ index: Int) -> UnifiedDiff.File {
    guard let package = DesignFixtures.pdfDiff.packages.first, package.files.indices.contains(index) else {
        fatalError("the pdf design diff has no file at \(index)")
    }
    return package.files[index]
}

/// The board's two flagged lines of pdf's SKILL.md: the `curl … | sh` on new line 12 and the `‹U+202E›` on 13.
private let pdfFlags = [DiffFlag(line: 12, kind: .risky), DiffFlag(line: 13, kind: .invisible)]

/// One file in the pane; SKILL.md carries the board's flags, every other file none.
private struct DiffPane: View {
    let file: UnifiedDiff.File
    var wrapsLines = false

    init(_ file: UnifiedDiff.File, wrapsLines: Bool = false) {
        self.file = file
        self.wrapsLines = wrapsLines
    }

    var body: some View {
        DiffView(file, flags: file.path.hasSuffix("SKILL.md") ? pdfFlags : [], wrapsLines: wrapsLines)
    }
}

/// The Components board's "Diff viewer" region: the file list on the grouped surface (dot, path, counts or word)
/// with the first file selected, then the pane, inside the region's hairline frame.
private struct DiffRegion: View {
    /// The board's `width: 170px` list.
    private static let listWidth: CGFloat = 170
    /// The board's `gap: 2px` between file rows; off the spacing scale, so named rather than written.
    private static let fileListGap: CGFloat = 2

    var body: some View {
        HStack(spacing: 0) {
            fileList
                .frame(width: Self.listWidth)
                .background(Color.surfaceGrouped)
            Rectangle().fill(Color.separator).frame(width: Size.hairline)
            DiffPane(pdfFile(0))
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(Color.separator))
        .padding(Spacing.m)
        .background(Color.surfaceWindow)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: Self.fileListGap) {
            if let package = DesignFixtures.pdfDiff.packages.first {
                ForEach(package.files) { file in
                    fileRow(file)
                }
            }
        }
        .padding(Spacing.inline)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func fileRow(_ file: UnifiedDiff.File) -> some View {
        let flagged = file.path.hasSuffix("SKILL.md")
        let isBinary = file.change == .binary
        return HStack(spacing: Spacing.inline) {
            Circle()
                .fill(Color.statusDot(DiffFileHeader.severity(of: file.change, flagged: flagged)))
                .frame(width: DiffFileHeader.dotSize, height: DiffFileHeader.dotSize)
            Text(file.pathInSkill)
                .font(Font.Token.monoSmall)
                .foregroundStyle(isBinary ? Color.textSecondary : Color.textPrimary)
                .strikethrough(file.change == .removed)
                .lineLimit(1)
            Spacer(minLength: Spacing.xs)
            if let word = DiffCopy.word(for: file.change) {
                Text(word)
                    .font(isBinary ? Font.Token.caption : Font.Token.monoSmall)
                    .foregroundStyle(file.change == .removed ? Color.statusErrorText : Color.textSecondary)
            } else {
                if file.additions > 0 {
                    Text(DiffCopy.added(file.additions)).foregroundStyle(Color.statusOkText)
                        .font(Font.Token.monoSmall)
                }
                if file.deletions > 0 {
                    Text(DiffCopy.removed(file.deletions)).foregroundStyle(Color.statusErrorText)
                        .font(Font.Token.monoSmall)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.inline)
        .background(
            flagged ? Color.selectionSoft : Color.clear,
            in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        )
    }
}
