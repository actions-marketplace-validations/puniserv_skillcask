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
}
