import Foundation
import SkillcaskCore

/// The words of the Settings window (S14: Settings and Settings-States boards). Board strings are verbatim; the
/// GitHub limits (60 an hour signed out, 5 000 with a token) are GitHub's documented REST API limits, so the board's
/// sentence stays as drawn.
///
/// Invented (no board draws them): `chosenInSettings`, `toolNotFound`, `chooseTool`, `skillsShNotSet`,
/// `couldNotSaveSkillsSh`, `skillsShNotSaved`, `gitHubUnknown`, `gitHubSignedIn`, `signOut`, `unknownNote`,
/// `couldNotSignIn`, `couldNotSignOut`, `redacted`, `tokenStored`, `tokenStoredByHelper`, `tokenNoteNeutral`,
/// `skillsShSideEffect`, `credentialsNotSaved`, `refusedVariable`, `removeVariable` (the board's
/// aria-label "Remove" with the name), `adoptedSummary(folders:bytes:)`'s singular and empty forms, `noAdopted`,
/// and the forms of `sourcesSearched(_:project:)` without a project or without project sources.
public enum SettingsCopy {
    // MARK: - Tabs

    public static let general = "General"
    public static let search = "Search"
    public static let updates = "Updates"
    public static let advanced = "Advanced"

    // MARK: - General

    public static let commandLineTool = "Command-line tool:"
    public static let choose = "Choose…"
    /// The open panel's button for Choose…. Invented.
    public static let chooseTool = "Use This Tool"
    public static let foundAutomatically = "found automatically"
    /// The tool was picked with Choose…. Invented.
    public static let chosenInSettings = "chosen in Settings"
    public static let useDetected = "Use the detected one"
    /// No tool located (the onboarding sheet explains). Invented.
    public static let toolNotFound = "Not found"

    /// `Version 0.9.4 · found automatically` (the board's line before its link).
    public static func toolLine(version: Version, configured: Bool) -> String {
        "Version \(version) · " + (configured ? chosenInSettings : foundAutomatically)
    }

    public static let openAtLaunch = "Open at launch:"
    public static let lastScopeUsed = "Last scope used"
    /// `Or always My Skills.`
    public static let openAtLaunchNote = "Or always \(ShellCopy.personalScope)."

    public static let recentProjects = "Recent projects:"
    public static let clearRecent = "Clear Recent"
    public static let privacy =
        "Nothing here leaves your Mac. The app has no account, no telemetry and no cloud features."

    // MARK: - Search

    public static let alsoSearchSkillsSh = "Also search skills.sh:"

    /// The sentence beside the switch; the view draws `skillsShStored(_:)` in mono where the board does.
    public static let skillsShNote =
        "Your search text is sent to skills.sh when you use Add Skill…. Packagist and your project’s own sources are always searched."

    /// `Stored as search.skills-sh = true in config.toml.`, split around the mono key.
    public static let storedAs = "Stored as"
    public static let inConfigToml = "in config.toml."

    /// The mono fragment: `search.skills-sh = true`.
    public static func skillsShStored(_ on: Bool) -> String {
        "search.skills-sh = \(on)"
    }

    /// config.toml does not set it. Invented.
    public static let skillsShNotSet = "Not set in config.toml yet; Add Skill… asks the first time you search."
    /// What changing the switch does, said before it is flipped: the CLI saves the setting only as part of a
    /// search (`search --remember` needs a query). Invented.
    public static let skillsShSideEffect =
        "Changing this runs one search for “\(CLISettingsStore.rememberQuery)” on Packagist, and on skills.sh when "
        + "turned on, so the command-line tool can save it."
    /// Under the tool line while a sheet or the Remove alert is open in the main window: Choose… and "Use the
    /// detected one" would rebuild what it works on. Invented.
    public static let closeSheetFirst = "Close the open sheet in the main window to change the tool."
    /// Invented.
    public static let couldNotSaveSkillsSh = "Couldn’t save the skills.sh setting."
    /// Why, when the run itself succeeded but the file did not change. Invented.
    public static let skillsShNotSaved = "config.toml did not change."

    public static let sourcesSearchedLabel = "Sources searched:"

    /// `Packagist, plus the sources of the open project (acme for api). GitHub results appear only where policy
    /// allows them.`; without project sources the parenthesis goes (invented form).
    public static func sourcesSearched(_ sources: [String], project: String?) -> String {
        let named = project.flatMap { sources.isEmpty ? nil : " (\(sources.joined(separator: ", ")) for \($0))" } ?? ""
        return "Packagist, plus the sources of the open project\(named). "
            + "GitHub results appear only where policy allows them."
    }

    /// The names the sentence gives for a project: its allowed sources, without Packagist and GitHub, which the
    /// sentence names apart.
    public static func projectSources(_ repositories: [StatusDocument.Repository]) -> [String] {
        repositories.filter { $0.allowed && $0.name != "packagist" && $0.type != "github" }.map(\.name)
    }

    public static let searchFooter =
        "Results are never ranked or filtered by the app; order and install counts come from the sources as the command-line tool returns them."

    // MARK: - Updates

    public static let checkOnOpen = "Check for updates when a project opens:"
    public static let checkOnOpenNote = "Asks each source what is newer. Off, you check with Refresh ⌘R."
    public static let gitHub = "GitHub:"
    public static let signedOut = "Signed out"
    /// No command tells whether a token is stored without returning it. Invented.
    public static let gitHubUnknown = "Unknown"
    /// This session stored a token. Invented.
    public static let gitHubSignedIn = "Signed in"
    public static let signIn = "Sign in to GitHub…"
    /// Runs `auth remove`. Invented.
    public static let signOut = "Sign Out"
    public static let signedOutNote =
        "Signed out, GitHub allows 60 checks per hour from this Mac. With many GitHub-sourced skills, checks can stall until the hour ends. A token raises the limit to 5 000."
    /// The same note when the app cannot know whether a token is stored. Invented (the board's first clause
    /// reworded).
    public static let unknownNote =
        "Without a token, GitHub allows 60 checks per hour from this Mac. With many GitHub-sourced skills, checks can stall until the hour ends. A token raises the limit to 5 000."
    public static let gitHubToken = "GitHub token:"
    public static let tokenPlaceholder = "ghp_… or a fine-grained token"
    public static let save = "Save"
    public static let tokenNote =
        "Stored in your Keychain by the command-line tool; the app never reads it back. Needs only public-repo read access."
    /// The token field's note before the helper is known (the board's sentence claims the Keychain, which holds
    /// only for git's osxkeychain helper). Invented.
    public static let tokenNoteNeutral =
        "Stored with git's credential helper by the command-line tool; the app never reads it back. "
        + "Needs only public-repo read access."
    /// After a Save that the CLI stored with osxkeychain. Invented.
    public static let tokenStored = "Token stored in your Keychain."
    /// After a Save stored by another helper. Invented.
    public static let tokenStoredByHelper = "Token stored by git's credential helper."
    /// Invented.
    public static let couldNotSignIn = "Couldn’t sign in to GitHub."
    /// Invented.
    public static let couldNotSignOut = "Couldn’t sign out of GitHub."
    /// What replaces a token if any text would ever contain it. Invented.
    public static let redacted = "••••"

    // MARK: - Advanced

    public static let environmentTitle = "Environment variables for the command-line tool"
    public static let name = "Name"
    public static let value = "Value"
    public static let addVariable = "+ Add Variable"
    /// The remove button's glyph.
    public static let minus = "−"
    public static let environmentNote = "Applied to every run; the Activity log shows them."
    /// The board's aria-label, with the row's name. Invented.
    public static func removeVariable(_ name: String) -> String {
        name.isEmpty ? "Remove" : "Remove \(name)"
    }

    /// A value with credentials (URL userinfo or a token format). Invented.
    public static let credentialsNotSaved =
        "A value with a user name, password or token in it is used this session only and never saved; the table "
        + "masks it."

    /// A row the policy refuses. Invented.
    public static let refusedVariable =
        "Not applied: names use A–Z, 0–9 and _, and variables for policy, credentials, hosts, TLS, CI, git and "
        + "the app’s own output can’t be set here."

    public static let configurationFile = "Configuration file:"
    public static let openConfig = "Open config.toml"
    public static let adoptedCopies = "Adopted copies:"
    public static let revealInFinder = "Reveal in Finder"
    /// The adopted folder does not exist yet. Invented.
    public static let noAdopted = "None yet"

    /// `4 folders · 1.2 MB` (singular form invented).
    public static func adoptedSummary(folders: Int, bytes: Int64) -> String {
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return "\(folders) \(folders == 1 ? "folder" : "folders") · \(size)"
    }

    public static let activity = "Activity:"
    public static let showActivity = "Show Activity ⌥⌘L"
    public static let activityNote = "Only this session; nothing is written to disk by the app."
    public static let policyNote =
        "Policy (allowed sources, minimum release age, enforced settings) is read-only here; it lives in config.toml and skills.toml."
}
