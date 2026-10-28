import SkillcaskCore
import SkillcaskDomain

/// The words of the window chrome, verbatim from the Main board and the designer's notes: the toolbar, the menu
/// bar, the sidebar sections and the list header. Views never spell these themselves.
public enum ShellCopy {
    // MARK: - Sidebar (Main board)

    public static let personal = "Personal"
    public static let projects = "Projects"
    /// The personal scope's row.
    public static let personalScope = "My Skills"
    /// The sidebar's bottom line and the File menu item; the real shortcut is bound in `SkillcaskCommands`.
    public static let openFolder = EmptyCopy.openFolder
    public static let openFolderShortcutHint = EmptyCopy.openFolderShortcut
    public static let addProject = "Add project"
    public static let scopesLabel = "Scopes"

    /// The name of a scope as the toolbar title and the outcome toast use it.
    public static func name(of scope: Scope) -> String {
        switch scope {
        case .personal: personalScope
        case .project(let url): AppStore.name(of: url)
        }
    }

    // MARK: - Toolbar (designer's note)

    public static let addSkill = EmptyCopy.addSkill
    public static let updateAll = "Update All"
    public static let sync = "Sync"
    public static let check = "Check"
    public static let moreActions = "More actions"
    public static let showActivity = "Show Activity"
    public static let revealManifest = "Reveal skills.toml"
    public static let openInTerminal = "Open in Terminal"
    /// What VoiceOver reads for the Update All badge is `CountBadge`'s; the button's own help text.
    public static let updateAllHelp = "Update every package with a newer version inside its range"
    public static let syncHelp = "Install exactly what skills.lock pins"
    public static let checkHelp = "Run the checks without changing anything"

    // MARK: - List header (Main board)

    /// `Search 14 skills  ⌘F`: the search field's placeholder.
    public static func searchPlaceholder(count: Int) -> String {
        "Search \(count) \(count == 1 ? "skill" : "skills")  ⌘F"
    }

    public static let searchLabel = "Search skills"
    public static let sortBy = "Sort by"

    /// The sort menu's items (S2 note: "Name, State (worst first), Source").
    public static func sortTitle(_ order: SkillcaskDomain.SortOrder) -> String {
        switch order {
        case .name: "Name"
        case .state: "State (worst first)"
        case .source: "Source"
        }
    }

    /// The View menu's sort submenu title.
    public static let sortMenu = "Sort By"
    /// The subtitle of a project row whose folder has no skills.toml yet (Main board).
    public static let notSetUp = Labels.notSetUp
    public static let setUp = EmptyCopy.setUp
    public static let skillsLabel = "Skills"

    // MARK: - Menu bar (designer's note)

    public static let fileMenu = "File"
    public static let findProjects = EmptyCopy.findProjects
    public static let openRecent = "Open Recent"
    public static let skillMenu = "Skill"
    public static let update = "Update…"
    public static let remove = DetailCopy.remove
    public static let adopt = DetailCopy.adopt
    public static let revealInFinder = "Reveal in Finder"
    public static let scopeMenu = "Scope"
    public static let repair = "Repair"
    public static let refresh = "Refresh"
    public static let viewMenu = "View"
    public static let activity = "Activity"
    public static let find = "Find"
    public static let helpMenu = "Help"
    public static let help = "Skillcask Help"
    public static let readme = "README"
    public static let removeFromSidebar = EmptyCopy.removeFromSidebar

    // MARK: - Detail placeholders (until P3-3, P3-5 and P3-6 fill the tabs)

    /// The body of a tab that is not built yet; never shipped, the three tabs replace it.
    public static func placeholder(_ tab: DetailTab) -> String {
        "\(DetailCopy.tab(tab)) is not built yet."
    }

    // MARK: - Agents

    /// The agent names the boards write for the CLI's target ids (`claude`, `cursor`, `codex`); an unknown id is
    /// shown as the CLI prints it.
    public static func agentName(_ target: String) -> String {
        switch target {
        case "claude": "Claude Code"
        case "cursor": "Cursor"
        case "codex": "Codex"
        default: target
        }
    }
}
