import SkillcaskCore

/// What a skill's text mentions an agent could reach, from the five `audit --json` lists (D32): commands it
/// runs, hosts it contacts, paths it reads or writes, environment variables and scripts. Information, not a
/// finding: the Security tab shows it as chip groups, the Overview counts it in one phrase.
public struct Reach: Hashable, Sendable {
    /// `audit.commands`: `git log`, `curl`.
    public let commands: [String]
    /// `audit.network`: host names.
    public let network: [String]
    /// `audit.paths`: `docs/notes/`, `~/.netrc`.
    public let paths: [String]
    /// `audit.env`: variable names without `$`.
    public let env: [String]
    /// `audit.scripts`: relative script paths or URLs.
    public let scripts: [String]

    public init(commands: [String], network: [String], paths: [String], env: [String], scripts: [String]) {
        self.commands = commands
        self.network = network
        self.paths = paths
        self.env = env
        self.scripts = scripts
    }

    /// The reach of one `audit` row.
    public init(_ skill: AuditDocument.Skill) {
        self.init(
            commands: skill.commands, network: skill.network, paths: skill.paths, env: skill.env,
            scripts: skill.scripts)
    }

    /// The text mentions nothing an agent could reach.
    public var isEmpty: Bool {
        commands.isEmpty && network.isEmpty && paths.isEmpty && env.isEmpty && scripts.isEmpty
    }
}
