import AppKit
import SkillcaskCore

/// The few things the shell asks Finder, Terminal and the open panel for (toolbar ⋯ menu, File and Skill menus).
/// AppKit stays here so views and stores never import it for these.
@MainActor enum Workspace {
    /// `Reveal skills.toml`: selects the manifest of `scope` in Finder, the personal one in the config directory;
    /// its folder when the file is missing, the scope's root when that is missing too. The environment is the one
    /// `ProcessRunner` gives the CLI (`EnvironmentPolicy.default`), so `SKILLCASK_HOME` and `XDG_CONFIG_HOME`
    /// resolve as the CLI resolves them.
    static func revealManifest(of scope: Scope) {
        let manifest = scope.manifest(environment: EnvironmentPolicy.default.environment())
        let target =
            [manifest, manifest.deletingLastPathComponent()]
            .first { FileManager.default.fileExists(atPath: $0.path) } ?? scope.root
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
