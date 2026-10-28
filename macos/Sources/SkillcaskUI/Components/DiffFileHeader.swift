import SkillcaskDomain
import SwiftUI

/// The strip above a file's lines (ReviewUpdate board: `padding: 6px 12px`, hairline below, 11 pt in
/// `textSecondary`): the file's dot, its path inside the skill in `monoSmall` (`SKILL.md`, `scripts/ocr.py`, as
/// the file list writes it; struck through when the file is removed) and `+14 −3` in the ok and error text
/// colours, or the board's word for a file without counts (`new`, `removed`, `binary`). The dot is the file
/// list's 6 pt one: ok for an added file, error for a removed one, neutral for a modified or binary file, and
/// amber when a line in it is flagged ("Amber dot = contains a flagged line").
///
/// Declared deviation: the board's strip shows the file name and the hunk header currently scrolled into view
/// (`SKILL.md  @@ -8,9 +8,15 @@ Reading`). Tracking the visible hunk needs the sheet's scroll state, so this strip
/// shows dot, name and counts instead; the hunk-in-view readout is left to the sheet.
public struct DiffFileHeader: View {
    /// The boards' file-list dot: `width: 6px; height: 6px`, smaller than the row's `Size.statusDot`.
    nonisolated static let dotSize: CGFloat = 6
    /// The strip's `padding: 6px 12px`.
    nonisolated static let paddingV = Spacing.inline
    nonisolated static let paddingH = Spacing.m

    public let file: UnifiedDiff.File
    public let flags: [DiffFlag]

    public init(_ file: UnifiedDiff.File, flags: [DiffFlag] = []) {
        self.file = file
        self.flags = flags
    }

    /// The dot colour of a file in the list and the strip.
    nonisolated public static func severity(of change: UnifiedDiff.File.Change, flagged: Bool) -> Severity {
        guard !flagged else { return .warning }
        switch change {
        case .added: return .ok
        case .removed: return .error
        case .modified, .modeOnly, .binary, .tooLarge: return .neutral
        }
    }

    public var body: some View {
        HStack(spacing: Spacing.inline) {
            Circle()
                .fill(Color.statusDot(Self.severity(of: file.change, flagged: !flags.isEmpty)))
                .frame(width: Self.dotSize, height: Self.dotSize)
            Text(file.pathInSkill)
                .font(Font.Token.monoSmall)
                .foregroundStyle(Color.textSecondary)
                .strikethrough(file.change == .removed)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Spacing.s)
            trailing
        }
        .padding(.vertical, Self.paddingV)
        .padding(.horizontal, Self.paddingH)
        .frame(maxWidth: .infinity)
        .background(Color.surfaceWindow)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.separator).frame(height: Size.hairline)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Subviews

    @ViewBuilder private var trailing: some View {
        if let word = DiffCopy.word(for: file.change) {
            Text(word)
                .font(Font.Token.caption)
                .foregroundStyle(file.change == .removed ? Color.statusErrorText : Color.textSecondary)
        } else {
            HStack(spacing: Spacing.xs) {
                if file.additions > 0 {
                    Text(DiffCopy.added(file.additions)).foregroundStyle(Color.statusOkText)
                }
                if file.deletions > 0 {
                    Text(DiffCopy.removed(file.deletions)).foregroundStyle(Color.statusErrorText)
                }
            }
            .font(Font.Token.monoSmall)
        }
    }
}

#Preview("DiffFileHeader, light") {
    DiffFileHeaderSample()
}

#Preview("DiffFileHeader, dark") {
    DiffFileHeaderSample()
        .preferredColorScheme(.dark)
}

/// Every file of the pdf diff as a strip: modified with flags, added, modified, removed, binary.
private struct DiffFileHeaderSample: View {
    var body: some View {
        VStack(spacing: 0) {
            if let package = DesignFixtures.pdfDiff.packages.first {
                ForEach(package.files) { file in
                    DiffFileHeader(
                        file, flags: file.path.hasSuffix("SKILL.md") ? [DiffFlag(line: 12, kind: .risky)] : [])
                }
            }
        }
        .frame(width: 600)
        .background(Color.surfaceWindow)
    }
}
