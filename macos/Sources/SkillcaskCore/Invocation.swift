import Foundation

/// One `skillcask` command line, built from typed parts so the app never concatenates strings into argv.
///
/// Rendering rules, all tested: `-g` comes first and only for `.personal`; `--json` is added where the CLI accepts
/// it; every value that comes from data (package, skill, query, path) follows a literal `--`, so a name starting with
/// `-` can never become a flag.
public struct Invocation: Hashable, Sendable {
    public enum InfoTarget: Hashable, Sendable {
        /// `info <skill>`: offline, reads the lock and the store (6 ms).
        case skill(String)
        /// `info <vendor/name>`: downloads the package's dist every time (seconds); never run it on selection.
        case package(String)
    }

    /// `search --skills-sh` / `--no-skills-sh` for one run, remembered in config.toml with `--remember`.
    public enum SkillsShChoice: Hashable, Sendable {
        case include
        case exclude
    }

    public enum Command: Hashable, Sendable {
        case version
        case status
        case audit
        case outdated
        case doctor(fix: Bool)
        case info(InfoTarget)
        case search(query: String, skillsSh: SkillsShChoice?, remember: Bool)
        /// `projects <dirs>`: the CLI refuses `-g`, so the scope only sets the working directory.
        case projects(roots: [URL])
        /// `diff [package]`: unified diff of what `update` would change; text, not JSON (until `diffJSON`).
        case diff(package: String?)
        case initialize
        case install(frozen: Bool)
        case update(packages: [String])
        case add(spec: String, repository: String?, adopt: Bool, rename: [String: String], skills: [String])
        case remove(packages: [String])
        /// `auth set <host>`: the token goes to stdin, never into argv.
        case authSet(host: String, username: String?)
        case authRemove(host: String)
    }

    public enum Stdin: Hashable, Sendable {
        /// `/dev/null`: the CLI only prompts on a terminal, so it never waits on us.
        case null
        /// Written and closed before the child reads; used for `auth set`. Never logged.
        case text(String)
    }

    public let scope: Scope
    public let command: Command
    public let capabilities: Capabilities
    public let stdin: Stdin

    public init(_ command: Command, in scope: Scope, capabilities: Capabilities, stdin: Stdin = .null) throws(CLIError)
    {
        try Self.validate(command, capabilities: capabilities)
        self.command = command
        self.scope = scope
        self.capabilities = capabilities
        self.stdin = stdin
    }

    /// Changes skills.toml, skills.lock, the store or the links: serialised per scope by `MutationQueue`.
    public var isMutation: Bool {
        switch command {
        case .initialize, .install, .update, .add, .remove, .doctor(fix: true): true
        default: false
        }
    }

    /// May talk to a registry or GitHub; shown with a network affordance and a Retry on exit 3.
    public var needsNetwork: Bool {
        switch command {
        case .outdated, .search, .diff, .info(.package), .install, .update, .add: true
        default: false
        }
    }

    /// `--json` is on the command line, so stdout is a document (even on exit 1 for the read-only verbs).
    public var expectsDocument: Bool {
        switch command {
        case .status, .audit, .outdated, .doctor, .info, .search, .projects: true
        case .initialize, .install, .update, .add, .remove: capabilities.supports(.jsonMutations)
        case .version, .diff, .authSet, .authRemove: false
        }
    }

    public var argv: [String] {
        var args: [String] = []
        if scope.isPersonal && acceptsGlobal {
            args.append("-g")
        }
        args += words
        return args
    }

    /// `skillcask -g add -- vendor/name`, for the Activity drawer and logs.
    public var displayCommand: String {
        (["skillcask"] + argv.map(Self.quoted)).joined(separator: " ")
    }

    // MARK: - Rendering

    private var acceptsGlobal: Bool {
        switch command {
        case .version, .projects: false
        default: true
        }
    }

    private var json: [String] {
        expectsDocument ? ["--json"] : []
    }

    private var words: [String] {
        switch command {
        case .version:
            return ["--version"]
        case .status:
            return ["status"] + json
        case .audit:
            return ["audit"] + json
        case .outdated:
            return ["outdated"] + json
        case .doctor(let fix):
            return ["doctor"] + (fix ? ["--fix"] : []) + json
        case .info(.skill(let name)), .info(.package(let name)):
            return ["info"] + json + ["--", name]
        case .search(let query, let choice, let remember):
            var flags: [String] = []
            switch choice {
            case .include: flags.append("--skills-sh")
            case .exclude: flags.append("--no-skills-sh")
            case nil: break
            }
            if remember {
                flags.append("--remember")
            }
            return ["search"] + json + flags + ["--", query]
        case .projects(let roots):
            return ["projects"] + json + ["--"] + roots.map(\.path)
        case .diff(let package):
            return ["diff"] + (package.map { ["--", $0] } ?? [])
        case .initialize:
            return ["init"] + json
        case .install(let frozen):
            return ["install"] + (frozen ? ["--frozen"] : []) + json
        case .update(let packages):
            return ["update"] + json + (packages.isEmpty ? [] : ["--"] + packages)
        case .add(let spec, let repository, let adopt, let rename, let skills):
            var flags: [String] = []
            if let repository {
                flags += ["--repository", repository]
            }
            if adopt {
                flags.append("--adopt")
            }
            for (old, new) in rename.sorted(by: { $0.key < $1.key }) {
                flags += ["--rename", "\(old)=\(new)"]
            }
            for skill in skills {
                flags += ["--skill", skill]
            }
            return ["add"] + flags + json + ["--", spec]
        case .remove(let packages):
            return ["remove"] + json + ["--"] + packages
        case .authSet(let host, let username):
            return ["auth", "set"] + (username.map { ["--username", $0] } ?? []) + ["--", host]
        case .authRemove(let host):
            return ["auth", "remove", "--", host]
        }
    }

    private static func validate(_ command: Command, capabilities: Capabilities) throws(CLIError) {
        switch command {
        case .info(.skill(let name)), .info(.package(let name)):
            try require(!name.isEmpty, "info needs a package or skill name")
        case .search(let query, let choice, let remember):
            try require(!query.isEmpty, "search needs a query")
            try require(!remember || choice != nil, "search --remember needs a skills.sh choice")
        case .projects(let roots):
            try require(!roots.isEmpty, "projects needs at least one directory")
        case .diff(let package):
            try require(package?.isEmpty != true, "diff needs a package name or none")
        case .add(let spec, let repository, _, let rename, let skills):
            try require(!spec.isEmpty, "add needs a package spec")
            try require(repository?.isEmpty != true, "add --repository needs a name")
            if !rename.isEmpty {
                try feature(.addRename, capabilities, "add --rename")
                try require(rename.allSatisfy { !$0.key.isEmpty && !$0.value.isEmpty }, "add --rename needs old=new")
            }
            if !skills.isEmpty {
                try feature(.addSkill, capabilities, "add --skill")
                try require(skills.allSatisfy { !$0.isEmpty }, "add --skill needs a skill name")
            }
        case .remove(let packages):
            try require(!packages.isEmpty && packages.allSatisfy { !$0.isEmpty }, "remove needs at least one package")
        case .update(let packages):
            try require(packages.allSatisfy { !$0.isEmpty }, "update needs package names or none")
        case .authSet(let host, let username):
            try require(!host.isEmpty, "auth set needs a host")
            try require(username?.isEmpty != true, "auth set --username needs a name")
        case .authRemove(let host):
            try require(!host.isEmpty, "auth remove needs a host")
        case .version, .status, .audit, .outdated, .doctor, .initialize, .install:
            break
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws(CLIError) {
        if !condition {
            throw .invalidInvocation(message)
        }
    }

    private static func feature(
        _ feature: Capabilities.Feature, _ capabilities: Capabilities, _ name: String
    ) throws(CLIError) {
        if !capabilities.supports(feature) {
            throw .unsupported(feature: name)
        }
    }

    private static func quoted(_ arg: String) -> String {
        let safe = arg.allSatisfy { $0.isLetter || $0.isNumber || "-_./=:@^~+,".contains($0) }
        return safe && !arg.isEmpty ? arg : "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
