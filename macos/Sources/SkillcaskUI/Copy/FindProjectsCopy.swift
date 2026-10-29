import Foundation

/// The words of the Find Projects sheet (Flow-F1 step 4: "Find Projects in Folder… runs `projects <dir>` and lists
/// hits in a checklist sheet; chosen ones are added"). The board draws no sheet, so every string here is invented;
/// the folder is shown `~`-abbreviated.
public enum FindProjectsCopy {
    /// `Find Projects in work`: the sheet's title, with the chosen folder's name.
    public static func title(folder: String) -> String {
        "Find Projects in \(folder)"
    }

    /// The header sentence while `projects` runs.
    public static func looking(in path: String) -> String {
        "Looking for folders with a skills.toml under \(path)…"
    }

    /// The header sentence over the checklist: `Found 3 projects under ~/work. Choose the ones to add to the
    /// sidebar.`; one project reads `Found 1 project …`.
    public static func found(_ count: Int, in path: String) -> String {
        let projects = count == 1 ? "1 project" : "\(count) projects"
        return "Found \(projects) under \(path). Choose the ones to add to the sidebar."
    }

    /// The header sentence when every folder found is already listed: `All 3 projects under ~/work are already in
    /// the sidebar.`; one reads `The project under ~/work is already in the sidebar.`
    public static func allAdded(_ count: Int, in path: String) -> String {
        count == 1
            ? "The project under \(path) is already in the sidebar."
            : "All \(count) projects under \(path) are already in the sidebar."
    }

    /// The header sentence when nothing was found.
    public static func noneFound(in path: String) -> String {
        "No folder under \(path) has a skills.toml."
    }

    /// The line under `noneFound(in:)`: where a folder without one goes.
    public static let noneFoundHint = "Open Folder… adds a folder without one and offers Set Up."

    /// The trailing mark of a project the sidebar already lists (its checkbox ticked and disabled).
    public static let inSidebar = "In the sidebar"

    /// The primary button: `Add Project` for one, `Add 3 Projects` for several.
    public static func add(count: Int) -> String {
        count == 1 ? "Add Project" : "Add \(count) Projects"
    }

    /// The failure title when `projects` failed.
    public static let couldNotFind = "Couldn’t look for projects."
}
