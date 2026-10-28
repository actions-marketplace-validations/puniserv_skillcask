import SkillcaskCore
import SwiftUI

/// The sidebar (Main board): a `List` of scopes in two sections, Personal with the one "My Skills" row and
/// Projects with the recent project folders, each a `ScopeRow` with its `ScopeBadge`. Selection is the system's
/// (bound to `AppStore.selectedScope`). With no projects, the Overview-States hint block sits under the Projects
/// header; the bottom line repeats Open Folder… with its shortcut, which the File menu binds.
struct SidebarView: View {
    @Environment(AppStore.self) private var app

    var body: some View {
        @Bindable var app = app
        List(selection: $app.selectedScope) {
            Section(ShellCopy.personal) {
                ScopeRow(item: personal, attention: app.visitedStore(for: .personal)?.snapshot?.attention)
                    .tag(Scope.personal)
            }
            Section(ShellCopy.projects) {
                if app.projects.isEmpty {
                    hint
                } else {
                    ForEach(app.projects) { item in
                        ScopeRow(item: item, attention: app.visitedStore(for: item.scope)?.snapshot?.attention)
                            .tag(item.scope)
                            .contextMenu {
                                Button(ShellCopy.removeFromSidebar) { app.removeFromSidebar(item.scope) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel(ShellCopy.scopesLabel)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    // MARK: - Derived

    private var personal: AppStore.ScopeItem {
        app.item(for: .personal) ?? AppStore.ScopeItem(scope: .personal, name: ShellCopy.personalScope, subtitle: nil)
    }

    // MARK: - Subviews

    private var hint: some View {
        EmptyState(
            icon: "folder.badge.plus", title: EmptyCopy.noProjectsTitle, body: EmptyCopy.noProjectsBody,
            actions: [.primary(EmptyCopy.openFolder, shortcutHint: EmptyCopy.openFolderShortcut, perform: openFolder)],
            style: .dashed
        )
        .listRowInsets(EdgeInsets(top: Spacing.xs, leading: 0, bottom: Spacing.xs, trailing: 0))
    }

    /// The board's bottom line: a plus glyph and "Open Folder… ⌘O" in secondary 11 pt, over a hairline.
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.separator)
                .frame(height: Size.hairline)
            Button(action: openFolder) {
                HStack(spacing: Spacing.inline) {
                    Image(systemName: "plus")
                        .font(Font.Token.callout)
                    Text(ShellCopy.openFolder + " " + ShellCopy.openFolderShortcutHint)
                        .font(Font.Token.caption)
                }
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ShellCopy.addProject)
        }
    }

    private func openFolder() {
        if let folder = Workspace.chooseFolder(prompt: EmptyCopy.openFolder) {
            app.open(folder: folder)
        }
    }
}
