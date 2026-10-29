import Foundation
import SkillcaskDomain

/// The words of the empty and "nothing to show" states (Overview-States, List-States, Contents-States and the
/// Components board's empty-state block), verbatim. `EmptyState` draws them; views never spell them.
///
/// Text between backticks is a file or folder name the board sets in `type.mono.small` (`skills.toml`,
/// `.claude/`); `EmptyState` draws those runs in mono and `plain(_:)` gives the sentence without the marks.
public enum EmptyCopy {
    // MARK: - No projects yet (Overview-States)

    public static let noProjectsTitle = "Add a project to manage its skills"
    public static let noProjectsBody =
        "A project is any folder with a `skills.toml`. Skillcask can also set one up for you. You can drop a folder "
        + "on the sidebar."
    public static let openFolder = "Open Folder…"
    /// The shortcut the board writes inside the Open Folder… button; the screen binds the real `⌘O`.
    public static let openFolderShortcut = "⌘O"
    public static let findProjects = "Find Projects in Folder…"

    // MARK: - Folder without skills.toml (Overview-States)

    public static let notSetUpTitle = "This folder doesn’t use Skillcask yet"
    public static let setUp = "Set Up"
    public static let removeFromSidebar = "Remove from Sidebar"

    /// One agent Set Up links skills into: its name and the folder it reads (`Claude Code`, `.claude/`).
    public struct Agent: Hashable, Sendable {
        public let name: String
        public let folder: String

        public init(name: String, folder: String) {
            self.name = name
            self.folder = folder
        }
    }

    /// `Set Up creates skills.toml in this folder and links skills into the agents it finds here: Claude Code
    /// (.claude/) and Cursor (.cursor/). Nothing is downloaded.`; with no agent found, the agents clause is left
    /// out.
    public static func notSetUpBody(agents: [Agent]) -> String {
        let nothing = " Nothing is downloaded."
        guard !agents.isEmpty else {
            return "Set Up creates `skills.toml` in this folder." + nothing
        }
        let names = OutcomeCopy.list(agents.map { "\($0.name) (`\($0.folder)`)" })
        return "Set Up creates `skills.toml` in this folder and links skills into the agents it finds here: "
            + names + "." + nothing
    }

    // MARK: - Empty after Set Up (List-States, Components)

    public static let noSkillsTitle = "No skills yet"
    public static let noSkillsBody =
        "skills.toml is ready. Add a skill from Packagist, GitHub or a git URL, or adopt one another tool installed."
    public static let addSkill = "Add Skill…"

    // MARK: - Filtered, no matches (List-States)

    /// `Nothing matches “postgres”`.
    public static func noMatchesTitle(query: String) -> String {
        "Nothing matches “\(query)”"
    }

    /// `in Updates. 1 skill matches in All.` / `3 skills match`; just `in Updates.` when nothing in All matches,
    /// and nil under All itself, where the title says everything.
    public static func noMatchesBody(filter: Filter, matchesInAll: Int) -> String? {
        guard filter != .all else { return nil }
        let scope = "in \(FilterCopy.title(filter))."
        switch matchesInAll {
        case ..<1: return scope
        case 1: return scope + " 1 skill matches in \(FilterCopy.title(.all))."
        default: return scope + " \(matchesInAll) skills match in \(FilterCopy.title(.all))."
        }
    }

    public static let showAll = "Show All"
    public static let clearSearch = "Clear Search"

    /// `Find “postgres” in sources…`: opens Add Skill with the query.
    public static func findInSources(query: String) -> String {
        "Find “\(query)” in sources…"
    }

    // MARK: - Contents: too large (Contents-States)

    public static let tooLargeTitle = "Too large to preview"
    public static let openInEditor = "Open in editor"

    /// `SKILL.md is 1.3 MB; the preview stops at 256 KB. The front matter and the security scan still cover the
    /// whole file.`
    public static func tooLargeBody(fileName: String, bytes: Int) -> String {
        "\(fileName) is \(size(bytes)); the preview stops at 256 KB. The front matter and the security scan still "
            + "cover the whole file."
    }

    /// `1.3 MB`, `48 KB`: binary units with the board's decimal spellings, one decimal for megabytes, and no locale
    /// so the separator is always a point.
    static func size(_ bytes: Int) -> String {
        let kib = 1024.0
        let value = Double(bytes)
        if value >= kib * kib {
            return String(format: "%.1f MB", value / (kib * kib))
        }
        return "\(Int((value / kib).rounded(.up))) KB"
    }

    // MARK: - Contents: unreadable (Contents-States)

    /// `Can’t read SKILL.md`.
    public static func unreadableTitle(fileName: String) -> String {
        "Can’t read \(fileName)"
    }

    public static let unreadableBody =
        "The file is missing or not readable by your user. Check the folder, then Check again. Nothing was changed."
    /// Reveals the folder that should hold the file (lowercase f, as the board writes it).
    public static let openContainingFolder = "Open folder"
    public static let check = "Check"

    // MARK: - Marks

    /// The sentence without its backtick marks, as a reader hears it.
    public static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "`", with: "")
    }
}
