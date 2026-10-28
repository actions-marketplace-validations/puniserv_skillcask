import SwiftUI

/// The sidebar hint under Projects until the first project is added (Onboarding-States "First launch"): a dashed
/// block with "Add a project to manage its skills" in secondary caption and two accent links, Open Folder… with
/// its shortcut and Find Projects in Folder…. The board draws it in a window at 2/3 scale; these are its
/// full-size values (`padding: 6px; gap: 4px; border-radius: 6px` → 8, 4, `Radius.m`).
struct SidebarHint: View {
    let onOpenFolder: () -> Void
    let onFindProjects: () -> Void

    /// Shown while the sidebar lists no project.
    static func isShown(projects: [AppStore.ScopeItem]) -> Bool {
        projects.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(EmptyCopy.noProjectsTitle)
                .font(Font.Token.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2, reservesSpace: true)
            link(EmptyCopy.openFolder + " " + EmptyCopy.openFolderShortcut, action: onOpenFolder)
            link(EmptyCopy.findProjects, action: onFindProjects)
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.m)
                .strokeBorder(Color.separatorStrong, style: Self.border))
    }

    /// The board's `border: 1px dashed var(--sep2)`, as `EmptyState` draws its dashed block.
    private static var border: StrokeStyle {
        EmptyState.border(for: .dashed) ?? StrokeStyle(lineWidth: Size.hairline)
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Font.Token.captionMedium)
                .foregroundStyle(Color.accent)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }
}
