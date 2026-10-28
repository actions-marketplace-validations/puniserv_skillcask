import SkillcaskDomain
import SwiftUI

/// The unified toolbar (Main board, designer's note): Add Skill… primary, Update All with its count badge, Sync,
/// Check, and the ⋯ menu with Show Activity, Reveal skills.toml and Open in Terminal. Enablement is
/// `ToolbarRules`; every action also lives in the menu bar (`SkillcaskCommands`, SUI-11), which carries the
/// shortcuts. Add Skill… and Update All set `AppStore.sheet`, which `MainWindow` presents through `SheetHost`.
struct ScopeToolbar: ToolbarContent {
    let app: AppStore
    let runner: ActionRunner
    let store: ScopeStore?

    private var snapshot: ScopeSnapshot? { store?.snapshot }

    /// The scope has data and nothing of its own is running.
    private var isIdle: Bool {
        guard let store, ToolbarRules.isLoaded(snapshot) else { return false }
        return !runner.isBusy(store.scope)
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                app.request(.addSkill(query: nil))
            } label: {
                Label(ShellCopy.addSkill, systemImage: "plus")
                    .fontWeight(.semibold)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .disabled(!app.isReady || store == nil || !ToolbarRules.isLoaded(snapshot) || app.isPresenting)
            Button {
                app.request(.updateAll)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Label(ShellCopy.updateAll, systemImage: "arrow.down.circle").labelStyle(.titleOnly)
                    CountBadge(ToolbarRules.updateAllCount(snapshot), severity: .update)
                }
            }
            .help(ShellCopy.updateAllHelp)
            .disabled(!isIdle || !ToolbarRules.canUpdateAll(snapshot) || app.isPresenting)
            Button {
                if let store {
                    runner.start(.sync, in: store)
                }
            } label: {
                Label(ShellCopy.sync, systemImage: "arrow.triangle.2.circlepath").labelStyle(.titleOnly)
            }
            .help(ShellCopy.syncHelp)
            .disabled(!isIdle || !ToolbarRules.canSync(snapshot))
            Button {
                if let store {
                    runner.start(.check, in: store)
                }
            } label: {
                Label(ShellCopy.check, systemImage: "stethoscope").labelStyle(.titleOnly)
            }
            .help(ShellCopy.checkHelp)
            .disabled(!isIdle)
            Menu {
                // The Activity drawer arrives with its task; the shortcut is registered now so the menu shows it.
                Button(ShellCopy.showActivity) {}
                    .keyboardShortcut("l", modifiers: [.command, .option])
                    .disabled(true)
                Divider()
                Button(ShellCopy.revealManifest) {
                    if let store {
                        Workspace.revealManifest(app.manifest(of: store.scope), root: store.scope.root)
                    }
                }
                Button(ShellCopy.openInTerminal) {
                    if let store {
                        Workspace.openInTerminal(store.scope)
                    }
                }
            } label: {
                Label(ShellCopy.moreActions, systemImage: "ellipsis.circle").labelStyle(.iconOnly)
            }
            .help(ShellCopy.moreActions)
            .disabled(store == nil)
        }
    }
}
