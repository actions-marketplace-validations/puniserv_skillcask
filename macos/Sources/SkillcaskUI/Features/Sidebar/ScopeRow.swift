import SkillcaskDomain
import SwiftUI

/// One sidebar row (Main board, Components "Project row"): the scope glyph in the Iris accent (a person for My
/// Skills, a folder for a project), the name in `textPrimary`, the path under it in `textSecondary` 11 pt for a
/// project, and the `ScopeBadge` at the trailing end. 30 pt tall, 40 with the subtitle (`Size.sidebarRow*`).
/// A project whose folder has no skills.toml yet draws the dashed `textTertiary` folder and "Not set up" in its
/// subtitle's place (the board's `infra-playbooks` row), the same dashed vocabulary as `StatusDot.notSetUp`.
/// Selection is drawn by the `List`, never here.
struct ScopeRow: View {
    let item: AppStore.ScopeItem
    /// The scope's attention once it was visited; nil draws no badge.
    let attention: Attention?

    /// The board's `stroke-dasharray="2 2"` on the not-set-up folder glyph.
    nonisolated static let dash: [CGFloat] = [2, 2]
    nonisolated static let dashWidth: CGFloat = 1.5

    var body: some View {
        HStack(spacing: Spacing.s) {
            glyph
                .frame(width: Size.iconSidebar, height: Size.iconSidebar)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(item.subtitle == nil ? Font.Token.body : Font.Token.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(Font.Token.caption)
                        .foregroundStyle(item.isSetUp ? Color.textSecondary : Color.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let attention {
                ScopeBadge(attention)
            }
        }
        .frame(height: item.subtitle == nil ? Size.sidebarRow : Size.sidebarRowSubtitle)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isSetUp ? "" : ShellCopy.notSetUp)
    }

    // MARK: - Derived

    /// The path, or "Not set up" in its place for a folder without skills.toml.
    private var subtitle: String? {
        guard item.subtitle != nil else { return nil }
        return item.isSetUp ? item.subtitle : ShellCopy.notSetUp
    }

    // MARK: - Subviews

    @ViewBuilder private var glyph: some View {
        if item.scope.isPersonal {
            Image(systemName: "person.crop.circle")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accent)
        } else if item.isSetUp {
            Image(systemName: "folder")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accent)
        } else {
            FolderOutline()
                .stroke(Color.textTertiary, style: StrokeStyle(lineWidth: Self.dashWidth, dash: Self.dash))
        }
    }
}

/// The board's folder path (`M1.5 4.5 … z` on a 16-unit box), scaled to its frame, so the dashed stroke matches
/// the dashed status dot rather than an SF Symbol's filled outline.
private struct FolderOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 16
        var path = Path()
        path.move(to: CGPoint(x: 1.5, y: 4.5))
        path.addQuadCurve(to: CGPoint(x: 3, y: 3), control: CGPoint(x: 1.5, y: 3))
        path.addLine(to: CGPoint(x: 6, y: 3))
        path.addLine(to: CGPoint(x: 7.5, y: 4.5))
        path.addLine(to: CGPoint(x: 13, y: 4.5))
        path.addQuadCurve(to: CGPoint(x: 14.5, y: 6), control: CGPoint(x: 14.5, y: 4.5))
        path.addLine(to: CGPoint(x: 14.5, y: 12))
        path.addQuadCurve(to: CGPoint(x: 13, y: 13.5), control: CGPoint(x: 14.5, y: 13.5))
        path.addLine(to: CGPoint(x: 3, y: 13.5))
        path.addQuadCurve(to: CGPoint(x: 1.5, y: 12), control: CGPoint(x: 1.5, y: 13.5))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: unit, y: unit).translatedBy(x: rect.minX, y: rect.minY))
    }
}
