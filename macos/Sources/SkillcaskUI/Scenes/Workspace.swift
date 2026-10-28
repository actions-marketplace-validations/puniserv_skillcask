import AppKit
import SkillcaskCore

/// The few things the shell asks Finder, Terminal and the open panel for (toolbar ⋯ menu, File and Skill menus).
/// AppKit stays here so views and stores never import it for these.
@MainActor enum Workspace {
    /// `Reveal skills.toml`: selects `manifest` in Finder (from `AppStore.manifest(of:)`, so the personal one is in
    /// the config directory the CLI uses); its folder when the file is missing, `root` when that is missing too.
    static func revealManifest(_ manifest: URL, root: URL) {
        let target =
            [manifest, manifest.deletingLastPathComponent()]
            .first { FileManager.default.fileExists(atPath: $0.path) } ?? root
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    /// `Reveal in Finder`: selects `url`.
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// `Open in Terminal`: a Terminal window in the scope's root.
    static func openInTerminal(_ scope: Scope) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(
            [scope.root], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Settings › Advanced, `Open config.toml`: the file in its default app; Finder at its folder when it does not
    /// exist yet (the CLI writes it on the first `--remember`), the nearest existing parent past that.
    static func openOrReveal(_ file: URL) {
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.open(file)
            return
        }
        var folder = file.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: folder.path) && folder.pathComponents.count > 1 {
            folder = folder.deletingLastPathComponent()
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Settings › General, `Choose…`: the system open panel for one file (the command-line tool).
    static func chooseFile(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// `Open Folder…` and `Find Projects in Folder…`: the system open panel for one directory.
    static func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Settings › Advanced "Show Activity": activates the app and brings a main window (any window that can be main
    /// other than the key one, which is Settings) to the front, unminimizing it. False when there is none, so the
    /// caller opens one.
    static func bringMainWindowForward() -> Bool {
        let key = NSApp.keyWindow
        guard
            let window = NSApp.windows.first(where: {
                $0 !== key && $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized)
            })
        else { return false }
        NSApp.activate()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }
}
