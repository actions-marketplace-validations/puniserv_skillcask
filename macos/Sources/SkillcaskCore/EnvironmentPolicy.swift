import Foundation

/// The environment every child gets. One place, so the rules the TUI follows (D41) hold for the app too:
/// no colour, no agent mode, the usual install locations on `PATH`, and nothing recovered from a login shell
/// (an app started from Finder has no `GITHUB_TOKEN`; the CLI's `auth set` keeps tokens in the Keychain).
public struct EnvironmentPolicy: Hashable, Sendable {
    /// Directories appended to `PATH` when missing: Homebrew, Intel Homebrew, cargo, so `git` and the CLI resolve.
    public var extraPaths: [String]
    /// Keys set by the user in Settings. Only `allowsOverride` keys apply: names must be `[A-Z_][A-Z0-9_]*` and not
    /// refused by the table on `forbidden`.
    public var overrides: [String: String]

    public static let `default` = EnvironmentPolicy()

    public init(extraPaths: [String] = Self.installLocations, overrides: [String: String] = [:]) {
        self.extraPaths = extraPaths
        self.overrides = overrides
    }

    public static let installLocations = [
        "/opt/homebrew/bin", "/usr/local/bin",
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cargo/bin").path,
    ]

    /// Keys that would change what the CLI prints or assumes; always removed.
    static let stripped = ["CLICOLOR_FORCE", "CLAUDECODE", "AI_AGENT"]
    static let protected = ["PATH", "HOME"]
    /// What the Settings table (P3-13) may set. Every variable the CLI reads (`rg 'env::var|var_os' src/`, 0.9.x)
    /// is classified here, so the table can never weaken policy, reroute credentials or hosts, or inject code:
    ///
    /// | Variable | CLI source | Class |
    /// |---|---|---|
    /// | `SKILLCASK_MIN_RELEASE_AGE`, `_ALLOW_RANGES`, `_PACKAGIST`, `_GITHUB_REQUIRES`, `_ALLOW_SOURCES`, `_DENY_PATTERNS` | policy.rs:16, 159-171 (`env_layer`) | refused: policy |
    /// | `SKILLCASK_GITHUB_API`, `GITHUB_API_URL` | github.rs:27, 35 | refused: host that receives the token |
    /// | `SKILLCASK_SKILLS_SH` | registry.rs:345 | refused: host that receives queries |
    /// | `SKILLCASK_GIT_CREDENTIALS` | credential.rs:17 | refused: credential source |
    /// | `GITHUB_TOKEN`, `GH_TOKEN` | http.rs:72 | refused: token |
    /// | `COMPOSER_AUTH`, `COMPOSER_HOME`, `APPDATA` | http.rs:62, 151, 156 | refused: credentials, auth.json path |
    /// | `XDG_*` (`XDG_CONFIG_HOME`) | http.rs:59, 158; scope.rs:46 | refused: auth.json path |
    /// | `SKILLCASK_CA_FILE` | http.rs:235 | refused: TLS trust roots |
    /// | `CI` | main.rs:241, 283, 293 | refused: makes installs frozen and non-interactive |
    /// | `NO_COLOR`, `SKILLCASK_AGENT`, `AI_AGENT`, `CLAUDECODE`, `CLICOLOR_FORCE` | ui.rs:28-36 | refused: output the app parses (this policy sets or strips them) |
    /// | `PATH`, `HOME`, `USERPROFILE` | scope.rs:34 | refused: binary lookup, home |
    /// | `DYLD_*`, `LD_*` | loader | refused: code injection |
    /// | `GIT_*`, `SSH_*`, `GCM_*` | git children (credential.rs:23, project.rs:617) | refused: git config, askpass, credential helpers |
    /// | `SKILLCASK_*` not listed as allowed | — | refused: a later CLI may read it as policy |
    /// | `SKILLCASK_HOME` | scope.rs:45 (moves config.toml with its enforced policy layer, policy.rs:177, and the personal auth.json, commands.rs:84, http.rs:65) | refused: policy and credential path, as `XDG_*` |
    /// | `SKILLCASK_LINK_MODE` | project.rs:310 | allowed: copy instead of symlink |
    /// | `SKILLCASK_CACHE_DIR` | not read by 0.9.x | allowed: drawn on the Settings board |
    /// | `WT_SESSION` | ui.rs:34 (Windows only) | allowed: no effect on macOS |
    /// | `HTTPS_PROXY`, `HTTP_PROXY`, `ALL_PROXY`, `NO_PROXY` and any other name | ureq, git | allowed |
    static let forbidden: Set<String> = [
        "SKILLCASK_MIN_RELEASE_AGE", "SKILLCASK_ALLOW_RANGES", "SKILLCASK_PACKAGIST", "SKILLCASK_GITHUB_REQUIRES",
        "SKILLCASK_ALLOW_SOURCES", "SKILLCASK_DENY_PATTERNS", "SKILLCASK_GITHUB_API", "GITHUB_API_URL",
        "SKILLCASK_SKILLS_SH", "SKILLCASK_GIT_CREDENTIALS", "GITHUB_TOKEN", "GH_TOKEN", "COMPOSER_AUTH",
        "COMPOSER_HOME", "APPDATA", "SKILLCASK_CA_FILE", "CI", "NO_COLOR", "SKILLCASK_AGENT", "AI_AGENT",
        "CLAUDECODE", "CLICOLOR_FORCE", "PATH", "HOME", "USERPROFILE",
    ]
    /// Name prefixes refused whole (see the table).
    static let forbiddenPrefixes = ["XDG_", "DYLD_", "LD_", "GIT_", "SSH_", "GCM_"]
    /// The only `SKILLCASK_` names the table may set.
    static let allowedSkillcask: Set<String> = ["SKILLCASK_LINK_MODE", "SKILLCASK_CACHE_DIR"]

    /// The child's environment, from the app's own.
    public func environment(from base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        for key in Self.stripped {
            env.removeValue(forKey: key)
        }
        env["NO_COLOR"] = "1"
        env["SKILLCASK_AGENT"] = "0"
        env["PATH"] = searchPath(from: base["PATH"]).joined(separator: ":")
        for (key, value) in overrides where Self.allowsOverride(key) {
            env[key] = value
        }
        return env
    }

    /// `PATH` entries in order, with `extraPaths` appended once.
    public func searchPath(from path: String?) -> [String] {
        var seen: Set<String> = []
        return ((path?.split(separator: ":").map(String.init) ?? []) + extraPaths)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Whether the Settings table may set `key`: a well-formed name that is not `forbidden`.
    public static func allowsOverride(_ key: String) -> Bool {
        guard isValidKey(key), !forbidden.contains(key) else { return false }
        if forbiddenPrefixes.contains(where: key.hasPrefix) {
            return false
        }
        return !key.hasPrefix("SKILLCASK_") || allowedSkillcask.contains(key)
    }

    /// The names of `overrides` this policy applies, sorted: what a run record shows (never the values).
    public var appliedOverrideNames: [String] {
        overrides.keys.filter(Self.allowsOverride).sorted()
    }

    /// `value` carries credentials: userinfo in a URL (`scheme://user:pass@host`, `scheme://token@host`) or a
    /// known token format anywhere in it (GitHub `ghp_`/`gho_`/`ghu_`/`ghs_`/`ghr_`/`github_pat_`, GitLab `glpat-`).
    public static func hasCredentials(_ value: String) -> Bool {
        value.range(of: userinfo, options: .regularExpression) != nil
            || value.range(of: tokenShape, options: .regularExpression) != nil
    }

    /// `value` with URL userinfo and token-shaped parts replaced by `mask`, for display.
    public static func masked(_ value: String, mask: String = "••••") -> String {
        var text = value.replacingOccurrences(
            of: #"(://)[^/?#\s@]*@"#, with: "$1\(mask)@", options: .regularExpression)
        text = text.replacingOccurrences(of: tokenShape, with: "$1\(mask)", options: .regularExpression)
        return text
    }

    private static let userinfo = #"[A-Za-z][A-Za-z0-9+.-]*://[^/?#\s]*@"#
    /// A token prefix and the token characters after it.
    private static let tokenShape = #"(ghp_|gho_|ghu_|ghs_|ghr_|github_pat_|glpat-)[A-Za-z0-9_-]+"#

    /// Whether Settings may write `value` to disk for `name`: the name is allowed and is not a refused name being
    /// typed (a prefix of one, so `GITHUB_TOKE` on the way to `GITHUB_TOKEN` is never stored with a value), and the
    /// value holds no URL credentials. Other rows keep their name on disk and their value in memory only.
    public static func mayStoreValue(name: String, value: String) -> Bool {
        guard allowsOverride(name), !hasCredentials(value) else { return false }
        return !forbidden.contains { $0.hasPrefix(name) } && !forbiddenPrefixes.contains { $0.hasPrefix(name) }
    }

    /// `[A-Z_][A-Z0-9_]*`.
    public static func isValidKey(_ key: String) -> Bool {
        guard let first = key.first, first == "_" || first.isUppercase && first.isASCII else { return false }
        return key.allSatisfy { $0 == "_" || $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }
}
