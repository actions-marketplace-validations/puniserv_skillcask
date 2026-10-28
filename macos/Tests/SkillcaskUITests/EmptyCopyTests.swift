import SkillcaskDomain
import SwiftUI
import Testing

@testable import SkillcaskUI

/// P2-11: the empty states say what the boards say, the no-matches builder counts in English, and only the dashed
/// style draws a border.
@Suite struct EmptyCopyTests {
    // MARK: - Board literals

    @Test func fixedStringsMatchTheBoards() {
        let expected: [(String, String)] = [
            (EmptyCopy.noProjectsTitle, "Add a project to manage its skills"),
            (
                EmptyCopy.plain(EmptyCopy.noProjectsBody),
                "A project is any folder with a skills.toml. Skillcask can also set one up for you. You can drop a "
                    + "folder on the sidebar."
            ),
            (EmptyCopy.openFolder, "Open Folder…"),
            (EmptyCopy.openFolderShortcut, "⌘O"),
            (EmptyCopy.findProjects, "Find Projects in Folder…"),
            (EmptyCopy.notSetUpTitle, "This folder doesn’t use Skillcask yet"),
            (EmptyCopy.setUp, "Set Up"),
            (EmptyCopy.removeFromSidebar, "Remove from Sidebar"),
            (EmptyCopy.noSkillsTitle, "No skills yet"),
            (
                EmptyCopy.noSkillsBody,
                "skills.toml is ready. Add a skill from Packagist, GitHub or a git URL, or adopt one another tool "
                    + "installed."
            ),
            (EmptyCopy.addSkill, "Add Skill…"),
            (EmptyCopy.showAll, "Show All"),
            (EmptyCopy.clearSearch, "Clear Search"),
            (EmptyCopy.tooLargeTitle, "Too large to preview"),
            (EmptyCopy.openInEditor, "Open in editor"),
            (
                EmptyCopy.unreadableBody,
                "The file is missing or not readable by your user. Check the folder, then Check again. Nothing was "
                    + "changed."
            ),
            (EmptyCopy.openContainingFolder, "Open folder"),
            (EmptyCopy.check, "Check"),
        ]
        for (actual, board) in expected {
            #expect(!actual.isEmpty)
            #expect(actual == board)
        }
    }

    @Test func notSetUpNamesTheAgentsFound() {
        let agents = [
            EmptyCopy.Agent(name: "Claude Code", folder: ".claude/"),
            EmptyCopy.Agent(name: "Cursor", folder: ".cursor/"),
        ]
        #expect(
            EmptyCopy.plain(EmptyCopy.notSetUpBody(agents: agents))
                == "Set Up creates skills.toml in this folder and links skills into the agents it finds here: Claude "
                + "Code (.claude/) and Cursor (.cursor/). Nothing is downloaded.")
        #expect(
            EmptyCopy.plain(EmptyCopy.notSetUpBody(agents: []))
                == "Set Up creates skills.toml in this folder. Nothing is downloaded.")
    }

    @Test func contentsStatesMatchTheBoard() {
        let file = DesignFixtures.apiDocsFile
        #expect(
            EmptyCopy.tooLargeBody(fileName: file.name, bytes: file.bytes)
                == "SKILL.md is 1.3 MB; the preview stops at 256 KB. The front matter and the security scan still "
                + "cover the whole file.")
        #expect(EmptyCopy.size(48 * 1024) == "48 KB")
        #expect(EmptyCopy.unreadableTitle(fileName: file.name) == DesignFixtures.unreadableFile.title)
    }

    // MARK: - No matches

    @Test func noMatchesEchoesTheQuery() {
        #expect(EmptyCopy.noMatchesTitle(query: DesignFixtures.noMatchesQuery) == "Nothing matches “postgres”")
        #expect(EmptyCopy.findInSources(query: "postgres") == "Find “postgres” in sources…")
    }

    @Test func noMatchesCountsInEnglish() {
        #expect(EmptyCopy.noMatchesBody(filter: .updates, matchesInAll: 1) == "in Updates. 1 skill matches in All.")
        #expect(EmptyCopy.noMatchesBody(filter: .updates, matchesInAll: 3) == "in Updates. 3 skills match in All.")
        #expect(EmptyCopy.noMatchesBody(filter: .notManaged, matchesInAll: 0) == "in Not managed.")
        #expect(EmptyCopy.noMatchesBody(filter: .all, matchesInAll: 0) == nil)
        let line =
            EmptyCopy.noMatchesTitle(query: "postgres") + " "
            + (EmptyCopy.noMatchesBody(filter: .updates, matchesInAll: 1) ?? "")
        #expect(line == "Nothing matches “postgres” in Updates. 1 skill matches in All.")
    }

    // MARK: - Style

    @Test func onlyTheDashedStyleDrawsABorderAndAFill() {
        let dashed = EmptyState.border(for: .dashed)
        #expect(dashed?.dash == [3, 3])
        #expect(dashed?.lineWidth == Size.hairline)
        #expect(EmptyState.border(for: .plain) == nil)
        #expect(EmptyState.fill(for: .dashed) == Color.surfaceCard)
        #expect(EmptyState.fill(for: .plain) == nil)
    }

    @Test func shortcutHintIsPartOfTheLabelOnly() {
        let action = EmptyState.Action.primary(EmptyCopy.openFolder, shortcutHint: EmptyCopy.openFolderShortcut) {}
        #expect(action.label == "Open Folder… ⌘O")
        #expect(action.title == "Open Folder…")
        #expect(EmptyState.Action.secondary(EmptyCopy.findProjects) {}.label == "Find Projects in Folder…")
    }
}
