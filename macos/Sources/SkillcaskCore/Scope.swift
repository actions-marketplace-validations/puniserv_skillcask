import Foundation

/// Where a command acts: the personal skills under the home directory (`skillcask -g`) or one project.
public enum Scope: Hashable, Sendable {
    case personal
    case project(URL)

    /// A project scope for a directory path, with `~`, `..` and symlinks in the path resolved.
    public static func project(at path: String) -> Scope {
        .project(URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL)
    }

    /// The directory the CLI runs in: the home directory for personal skills, the project root otherwise.
    public var root: URL {
        switch self {
        case .personal: FileManager.default.homeDirectoryForCurrentUser
        case .project(let url): url
        }
    }

    public var isPersonal: Bool {
        if case .personal = self { true } else { false }
    }

    /// The `skills.toml` the CLI reads for this scope: in the project root, or for personal skills in the
    /// config directory (D13). `environment` is the child's (`EnvironmentPolicy.environment()`), so overrides the
    /// CLI honours resolve the same way here.
    public func manifest(environment: [String: String]) -> URL {
        switch self {
        case .personal: Self.configDirectory(environment: environment, home: root).appending(path: "skills.toml")
        case .project(let url): url.appending(path: "skills.toml")
        }
    }

    /// The CLI's config directory, as `config_dir_of` in `src/scope.rs` resolves it: `$SKILLCASK_HOME`, else
    /// `$XDG_CONFIG_HOME/skillcask`, else `$HOME/.config/skillcask`. Empty values count as unset; `home` stands in
    /// when the environment has no `HOME`. Differs from `home()` in `src/scope.rs:33-35`, where `HOME=""` means no
    /// home (`-g` fails) and `USERPROFILE` is the Windows fallback; neither applies to the macOS app.
    public static func configDirectory(environment: [String: String], home: URL) -> URL {
        func set(_ key: String) -> URL? {
            environment[key].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        }
        if let dir = set("SKILLCASK_HOME") {
            return dir
        }
        if let xdg = set("XDG_CONFIG_HOME") {
            return xdg.appending(path: "skillcask", directoryHint: .isDirectory)
        }
        return (set("HOME") ?? home).appending(path: ".config/skillcask", directoryHint: .isDirectory)
    }
}
