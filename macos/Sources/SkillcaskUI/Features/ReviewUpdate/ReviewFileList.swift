import SkillcaskDomain
import SwiftUI

/// The review sheet's file list (ReviewUpdate board, left of the diff): `Files`, then one row per file with its
/// 6 pt dot (amber when a line in it is flagged), its path inside the skill in mono and `+14 −3` or the word for a
/// file without counts. Update All groups the files in one collapsible section per package (ReviewUpdate-States)
/// with the package's versions and `4 files · +31 −9 · 2 flagged lines`, and notes the skills left out by the
/// minimum release age. The selection is the system list selection; the legend closes the column.
struct ReviewFileList: View {
    @Bindable var review: ReviewStore

    /// The column's `padding: 8px`, around the legend.
    static let legendPadding = Spacing.s
    /// The heading's inset: the column's 8 pt plus the heading's own 8 pt, and 8 + 2 pt on top.
    static let headingPaddingH = Spacing.l
    static let headingPaddingTop = Spacing.rowGap

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !review.isAll {
                // The board's `.t2` heading (11 pt semibold, text2, `padding: 2px 8px 6px` inside the column's
                // 8 pt): drawn here, not as the sidebar list's section header, whose colour is the system's.
                Text(ReviewUpdateCopy.filesHeading)
                    .font(Font.Token.captionSemibold)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Self.headingPaddingH)
                    .padding(.top, Self.headingPaddingTop)
            }
            List(selection: $review.selection) {
                if review.isAll {
                    ForEach(review.packages) { package in
                        DisclosureGroup(isExpanded: expanded(package.name)) {
                            rows(of: package)
                        } label: {
                            PackageLabel(review: review, package: package)
                        }
                    }
                } else if let package = review.packages.first {
                    rows(of: package)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            VStack(alignment: .leading, spacing: Spacing.s) {
                if review.isAll {
                    ForEach(Array(review.waiting.enumerated()), id: \.offset) { _, group in
                        Text(ReviewUpdateCopy.notIncluded(group.skills, version: group.version))
                    }
                }
                Text(ReviewUpdateCopy.legend(withFlags: review.hasNewVersionFindings))
            }
            .font(Font.Token.caption)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Self.legendPadding)
        }
        .background(Color.surfaceGrouped)
    }

    private func rows(of package: UnifiedDiff.Package) -> some View {
        ForEach(package.files) { file in
            FileRow(file: file, flagged: !review.flags(for: file, in: package.name).isEmpty)
                .tag(ReviewStore.FileID(package: package.name, path: file.path))
        }
    }

    /// A section is open unless the user collapsed it.
    private func expanded(_ package: String) -> Binding<Bool> {
        Binding(
            get: { !review.collapsed.contains(package) },
            set: { open in
                if open {
                    review.collapsed.remove(package)
                } else {
                    review.collapsed.insert(package)
                }
            })
    }
}

/// One file: dot, path, counts or word.
private struct FileRow: View {
    let file: UnifiedDiff.File
    let flagged: Bool

    /// `.increased` on the selected row (system accent fill): the colours give way to the selection's text colour.
    @Environment(\.backgroundProminence) private var prominence

    private var isSelected: Bool {
        prominence == .increased
    }

    var body: some View {
        HStack(spacing: Spacing.inline) {
            Circle()
                .fill(Color.statusDot(DiffFileHeader.severity(of: file.change, flagged: flagged)))
                .frame(width: DiffFileHeader.dotSize, height: DiffFileHeader.dotSize)
            Text(file.pathInSkill)
                .font(Font.Token.monoSmall)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(pathColor))
                .strikethrough(file.change == .removed)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Spacing.xs)
            trailing
        }
        .accessibilityElement(children: .combine)
    }

    /// A binary, too-large or mode-only file reads in the secondary colour (ReviewUpdate board's `binary` row).
    private var pathColor: Color {
        switch file.change {
        case .binary, .tooLarge, .modeOnly: Color.textSecondary
        case .added, .modified, .removed: Color.textPrimary
        }
    }

    /// A count's colour: the status text colour, or the selection's text colour on the selected row.
    private func style(_ color: Color) -> AnyShapeStyle {
        isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(color)
    }

    @ViewBuilder private var trailing: some View {
        if let counts = ReviewStore.listCounts(file) {
            HStack(spacing: Spacing.xs) {
                if counts.additions > 0 {
                    Text(DiffCopy.added(counts.additions)).foregroundStyle(style(Color.statusOkText))
                }
                if counts.deletions > 0 {
                    Text(DiffCopy.removed(counts.deletions)).foregroundStyle(style(Color.statusErrorText))
                }
            }
            .font(Font.Token.monoSmall)
        } else if let word = DiffCopy.word(for: file.change) {
            Text(word)
                .font(Font.Token.caption)
                .foregroundStyle(style(file.change == .removed ? Color.statusErrorText : Color.textSecondary))
        }
    }
}

/// Update All's section label: the package's skill, its versions, and the section summary.
private struct PackageLabel: View {
    let review: ReviewStore
    let package: UnifiedDiff.Package

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.inline) {
                Text(review.name(of: package.name))
                    .font(Font.Token.bodyEmphasis)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(ReviewUpdateCopy.versions(from: package.from, to: package.to))
                    .font(Font.Token.monoSmall)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Text(summary)
                .font(Font.Token.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let totals = ReviewStore.totals(package)
        return ReviewUpdateCopy.sectionSummary(
            files: ReviewStore.countedFiles(package).count, additions: totals.additions, deletions: totals.deletions,
            flagged: review.hasNewVersionFindings ? review.flaggedCount(of: package) : nil)
    }
}
