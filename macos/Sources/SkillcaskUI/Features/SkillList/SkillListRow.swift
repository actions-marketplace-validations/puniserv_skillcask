import SkillcaskCore
import SkillcaskDomain
import SwiftUI

/// One row of the skills list: a `SkillRow` told whether it is selected, with the board's hover (Components board
/// "hover with actions"): `surfaceHover` behind an unselected row, and the trailing slot swapped for Update… and
/// the ⋯ menu (`SkillRowActions`). The actions only record the request on `AppStore.sheet` until the sheets land
/// (P3-6, P3-8); Reveal in Finder selects the row's folder.
struct SkillListRow: View {
    let entry: SkillEntry
    let scope: Scope
    let isSelected: Bool
    let isOffline: Bool
    let requiredBy: [String]

    @Environment(AppStore.self) private var app
    @State private var isHovering: Bool

    /// - Parameter hovering: Previews only: draws the row as hovered (a render has no pointer).
    init(
        entry: SkillEntry, scope: Scope, isSelected: Bool, isOffline: Bool, requiredBy: [String],
        hovering: Bool = false
    ) {
        self.entry = entry
        self.scope = scope
        self.isSelected = isSelected
        self.isOffline = isOffline
        self.requiredBy = requiredBy
        _isHovering = State(initialValue: hovering)
    }

    /// Where `.inset` draws the system selection from the list's edges (measured in the renders: 10 pt), so the
    /// hover fill lines up with the accent highlight.
    static let highlightInset = Spacing.rowGap

    var body: some View {
        SkillRow(
            entry, isSelected: isSelected, isOffline: isOffline, requiredBy: requiredBy,
            accessory: isHovering ? AnyView(controls) : nil
        )
        .contentShape(Rectangle())
        .listRowBackground(
            isHovering && !isSelected
                ? RoundedRectangle(cornerRadius: Radius.m).fill(Color.surfaceHover)
                    .padding(.horizontal, Self.highlightInset) : nil
        )
        .onHover { isHovering = $0 }
    }

    // MARK: - Derived

    private var actions: SkillRowActions {
        .resolve(entry, offline: isOffline)
    }

    // MARK: - Subviews

    /// `display: inline-flex; gap: 4px`: two small bordered controls.
    private var controls: some View {
        HStack(spacing: Spacing.xs) {
            if let package = actions.updatePackage {
                Button(ListCopy.update) { app.sheet = .update(package: package) }
            }
            if !actions.menu.isEmpty {
                Menu {
                    menuItems
                } label: {
                    Label(ListCopy.more, systemImage: "ellipsis").labelStyle(.iconOnly)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .help(ListCopy.more)
                .accessibilityLabel(ListCopy.more)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder private var menuItems: some View {
        ForEach(actions.menu, id: \.self) { item in
            Button(ListCopy.title(item)) { perform(item) }
        }
    }

    private func perform(_ item: SkillRowActions.MenuItem) {
        switch item {
        case .remove: app.sheet = .remove(skills: [entry.id])
        case .adopt: app.sheet = .adopt(skill: entry.id)
        case .revealInFinder:
            if let path = entry.path {
                Workspace.reveal(scope.root.appending(path: path))
            }
        }
    }
}
