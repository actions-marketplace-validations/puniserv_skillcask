import SkillcaskDomain
import SwiftUI

/// The menu bar (designer's note): File, Skill, Scope, View and Help, with the shortcuts, reaching the focused
/// window's stores through `FocusedValues` (SUI-11). View is SwiftUI's own menu with the filters, the sort order
/// and Activity inserted after its sidebar items. Items whose sheet is not built yet record the request on
/// `AppStore.sheet` (Add Skill…, Update…, Update All, Remove…, Adopt…); Activity waits for its drawer.
public struct SkillcaskCommands: Commands {
    @FocusedValue(\.appStore) private var app
    @FocusedValue(\.scopeStore) private var store
    @FocusedValue(\.actionRunner) private var runner
    @FocusedValue(\.focusSearch) private var focusSearch

    public init() {}

    private var selected: SkillEntry? { store?.selectedEntry }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(ShellCopy.openFolder) {
                if let folder = Workspace.chooseFolder(prompt: EmptyCopy.openFolder) {
                    app?.open(folder: folder)
                }
            }
            .keyboardShortcut("o")
            .disabled(app?.isReady != true)
            Button(ShellCopy.findProjects) {
                if let app, let folder = Workspace.chooseFolder(prompt: ShellCopy.findProjects) {
                    Task { await app.findProjects(under: folder) }
                }
            }
            .disabled(app?.isReady != true)
            Menu(ShellCopy.openRecent) {
                ForEach(app?.projects ?? []) { item in
                    Button(item.name) { app?.selectedScope = item.scope }
                }
            }
        }
        CommandGroup(after: .textEditing) {
            Button(ShellCopy.find) { focusSearch?.perform() }
                .keyboardShortcut("f")
                .disabled(focusSearch == nil)
        }
        CommandMenu(ShellCopy.skillMenu) {
            Button(ShellCopy.addSkill) { app?.sheet = .addSkill }
                .keyboardShortcut("n")
                .disabled(store == nil)
            Button(ShellCopy.update) {
                if let package = selected?.package {
                    app?.sheet = .update(package: package)
                }
            }
            .disabled(selected.map { DetailActions.updateTarget(of: $0) == nil } ?? true)
            Button(ShellCopy.updateAll) { app?.sheet = .updateAll }
                .disabled(!ToolbarRules.canUpdateAll(store?.snapshot))
            Divider()
            Button(ShellCopy.remove) {
                if let selected {
                    app?.sheet = .remove(skills: [selected.id])
                }
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(selected.map { !DetailActions.resolve($0, offline: false).showsRemove } ?? true)
            Button(ShellCopy.adopt) {
                if let selected {
                    app?.sheet = .adopt(skill: selected.id)
                }
            }
            .disabled(selected?.isNotManaged != true)
            Divider()
            Button(ShellCopy.revealInFinder) {
                if let store, let path = selected?.path {
                    Workspace.reveal(store.scope.root.appending(path: path))
                }
            }
            .disabled(selected?.path == nil)
        }
        CommandMenu(ShellCopy.scopeMenu) {
            Button(ShellCopy.sync) { start(.sync) }
                .disabled(!ToolbarRules.canSync(store?.snapshot) || isBusy)
            Button(ShellCopy.check) { start(.check) }
                .disabled(store?.snapshot == nil || isBusy)
            Button(ShellCopy.repair) { start(.repair) }
                .disabled(store?.snapshot == nil || isBusy)
            Divider()
            Button(ShellCopy.refresh) {
                if let store {
                    Task {
                        await store.refresh()
                        await store.checkUpdates()
                    }
                }
            }
            .keyboardShortcut("r")
            .disabled(store == nil)
        }
        // SwiftUI's own View menu (Show/Hide Sidebar, Enter Full Screen) gains the filters, the sort and Activity.
        CommandGroup(after: .sidebar) {
            Divider()
            if let store {
                @Bindable var store = store
                Picker(ShellCopy.viewMenu, selection: $store.filter) {
                    ForEach(Filter.allCases, id: \.self) { filter in
                        Text(FilterCopy.title(filter)).tag(filter)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
                Picker(ShellCopy.sortMenu, selection: $store.sort) {
                    ForEach(SkillcaskDomain.SortOrder.allCases, id: \.self) { order in
                        Text(ShellCopy.sortTitle(order)).tag(order)
                    }
                }
            }
            Divider()
            Button(ShellCopy.activity) {}
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(true)
        }
        CommandGroup(replacing: .help) {
            Link(ShellCopy.help, destination: Self.readme)
            Link(ShellCopy.readme, destination: Self.readme)
        }
    }

    /// The project README, where Skillcask Help and README both go until the app has help of its own.
    static let readme = URL(string: "https://github.com/puniserv/skillcask#readme") ?? URL(fileURLWithPath: "/")

    private var isBusy: Bool {
        guard let store, let runner else { return true }
        return runner.isBusy(store.scope)
    }

    private func start(_ action: ActionRunner.Action) {
        if let store, let runner {
            runner.start(action, in: store)
        }
    }
}
