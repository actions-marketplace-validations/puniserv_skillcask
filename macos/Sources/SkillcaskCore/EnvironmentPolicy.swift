import Foundation

/// The environment every child gets. One place, so the rules the TUI follows (D41) hold for the app too:
/// no colour, no agent mode, the usual install locations on `PATH`, and nothing recovered from a login shell
/// (an app started from Finder has no `GITHUB_TOKEN`; the CLI's `auth set` keeps tokens in the Keychain).
public struct EnvironmentPolicy: Hashable, Sendable {
    /// Directories appended to `PATH` when missing: Homebrew, Intel Homebrew, cargo, so `git` and the CLI resolve.
    public var extraPaths: [String]
    /// Keys set by the user in Settings. `PATH` and `HOME` cannot be overridden; names must be `[A-Z_][A-Z0-9_]*`.
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

    /// The child's environment, from the app's own.
    public func environment(from base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        for key in Self.stripped {
            env.removeValue(forKey: key)
        }
        env["NO_COLOR"] = "1"
        env["SKILLCASK_AGENT"] = "0"
        env["PATH"] = searchPath(from: base["PATH"]).joined(separator: ":")
        for (key, value) in overrides where Self.isValidKey(key) && !Self.protected.contains(key) {
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

    static func isValidKey(_ key: String) -> Bool {
        guard let first = key.first, first == "_" || first.isUppercase && first.isASCII else { return false }
        return key.allSatisfy { $0 == "_" || $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }
}
