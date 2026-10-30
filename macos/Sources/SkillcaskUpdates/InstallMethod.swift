import Foundation

/// How this copy of the app got where it runs, which decides the update steps the sheet shows. Read from the bundle
/// path and the disk only (D35): no network, no `brew` run.
public enum InstallMethod: Hashable, Sendable {
    /// `brew install --cask skillcask-app`: `brew update && brew upgrade skillcask skillcask-app`.
    case homebrew
    /// Gatekeeper's read-only copy of an app opened where it was unzipped (`/AppTranslocation/`). `original` is
    /// where the user's copy lies, when the system tells.
    case translocated(original: URL?)
    /// Anything else: the release page's zip.
    case direct
}

/// Detects the `InstallMethod` of a bundle path, with the disk injected for tests.
public struct InstallMethodDetector: Sendable {
    /// Where the cask moves the app.
    public static let applicationPath = "/Applications/Skillcask.app"
    /// The cask's folder for Apple silicon and Intel Homebrew.
    public static let caskrooms = ["/opt/homebrew/Caskroom/skillcask-app", "/usr/local/Caskroom/skillcask-app"]

    public let bundlePath: String
    private let fileExists: @Sendable (String) -> Bool
    private let resolve: @Sendable (String) -> String
    private let originalPath: @Sendable (String) -> String?

    /// - Parameters:
    ///   - bundlePath: `Bundle.main.bundlePath` in the app.
    ///   - fileExists: Whether a file or folder exists at a path.
    ///   - resolve: The path with every symlink resolved.
    ///   - originalPath: For a translocated path, the user's copy. The live default answers nil:
    ///     `SecTranslocateCreateOriginalPathForURL` is not in the SDK's public headers, and calling it through
    ///     `dlsym` would tie the app to a private symbol.
    public init(
        bundlePath: String, fileExists: @escaping @Sendable (String) -> Bool = InstallMethodDetector.onDisk,
        resolve: @escaping @Sendable (String) -> String = InstallMethodDetector.resolvingSymlinks,
        originalPath: @escaping @Sendable (String) -> String? = { _ in nil }
    ) {
        self.bundlePath = bundlePath
        self.fileExists = fileExists
        self.resolve = resolve
        self.originalPath = originalPath
    }

    public static let onDisk: @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    public static let resolvingSymlinks: @Sendable (String) -> String = {
        URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
    }

    /// Translocated when the path, as given or resolved, holds `/AppTranslocation/`; Homebrew when the resolved path
    /// is `/Applications/Skillcask.app` and a Caskroom folder for `skillcask-app` exists, or the resolved path lies
    /// inside one; else direct.
    public func detect() -> InstallMethod {
        let resolved = Self.trimmed(resolve(bundlePath))
        if [bundlePath, resolved].contains(where: { $0.contains("/AppTranslocation/") }) {
            return .translocated(original: originalPath(bundlePath).map { URL(fileURLWithPath: $0) })
        }
        if resolved == Self.applicationPath, Self.caskrooms.contains(where: fileExists) {
            return .homebrew
        }
        // Beyond D35's two checks, kept on purpose: a bundle path that resolves to a copy inside the Caskroom (a
        // symlink to it) belongs to the cask too, and `brew upgrade` replaces it.
        if Self.caskrooms.contains(where: { resolved.hasPrefix($0 + "/") }) {
            return .homebrew
        }
        return .direct
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
