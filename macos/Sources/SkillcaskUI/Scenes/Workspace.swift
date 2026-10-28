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

    /// `Open Folder…` and `Find Projects in Folder…`: the system open panel for one directory.
    static func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}
