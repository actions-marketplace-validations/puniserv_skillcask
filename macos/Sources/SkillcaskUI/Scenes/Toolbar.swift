import SkillcaskDomain
import SwiftUI

/// The unified toolbar (Main board, designer's note): Add Skill… primary, Update All with its count badge, Sync,
/// Check, and the ⋯ menu with Show Activity, Reveal skills.toml and Open in Terminal. Enablement is
/// `ToolbarRules`; every action also lives in the menu bar (`SkillcaskCommands`), which carries the
/// shortcuts. Add Skill… and Update All set `AppStore.sheet`, which `MainWindow` presents through `SheetHost`.
struct ScopeToolbar: ToolbarContent {
    let app: AppStore
    let runner: ActionRunner
    let store: ScopeStore?

    private var snapshot: ScopeSnapshot? { store?.snapshot }

    /// The scope has a skills.toml: a folder without one acts on nothing (its commands would reach a parent
    /// project), so every action but the ⋯ menu waits for Set Up.
    private var isSetUp: Bool {
        store.map { app.isSetUp($0.scope) } ?? false
    }

    /// Add Skill…: `ToolbarRules.canAddSkill`, the rule ⌘N and the empty list share.
    private var canAddSkill: Bool {
        isSetUp && ToolbarRules.canAddSkill(snapshot, isBusy: runner.isRunning)
    }

    /// The scope is set up, has data and no run is in flight.
    private var isIdle: Bool {
        isSetUp && ToolbarRules.isLoaded(snapshot) && !runner.isRunning
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
            .disabled(!app.isReady || !canAddSkill || app.isPresenting)
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
            .help(ActionRunner.syncResolves(snapshot) ? ShellCopy.resolveHelp : ShellCopy.syncHelp)
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
                // ⌥⌘L lives on View › Activity (the menu bar carries the shortcuts): registering it here as well
                // would fire both and toggle the drawer twice.
                Button(runner.isActivityShown ? ActivityCopy.hideActivity : ActivityCopy.showActivity) {
                    runner.toggleActivity()
                }
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
