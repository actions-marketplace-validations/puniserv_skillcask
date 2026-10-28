import Foundation
import UniformTypeIdentifiers

/// What the app may do with a path a package controls (a skill's folder, its SKILL.md, its repository link).
/// Package content is data only: a folder named `x.app` or a SKILL.md symlinked to a `.command` must never reach
/// `NSWorkspace.open`, which would launch it (a git clone sets no quarantine). So folders are only revealed in
/// Finder, a file opens only when it resolves to a plain-text regular file inside the skill's folder, and only in
/// the user's text editor (`Workspace.openAsText`), and a link opens only when it is http or https.
/// `Workspace.openAsText` must keep naming the plain-text app (`NSWorkspace.open(_:withApplicationAt:configuration:)`)
/// and never hand the file to `NSWorkspace.open(target)`: a `.md` hard-linked to an executable passes every check
/// here, and LaunchServices would then pick the handler from the file and could run it.
///
/// The checks read the file system (symlinks, file type) but decide nothing else, so tests run them on real
/// temporary folders.
enum SafeOpen {
    /// The file to open as text, or nil to refuse: `file` with its symlinks resolved, when that is a regular file
    /// inside `folder` (also resolved), named as text (`textExtensions`) and of a plain-text, non-script type.
    static func textFile(_ file: URL, inside folder: URL) -> URL? {
        let resolved = file.standardizedFileURL.resolvingSymlinksInPath()
        let base = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.pathComponents.count > base.pathComponents.count,
            Array(resolved.pathComponents.prefix(base.pathComponents.count)) == base.pathComponents
        else { return nil }
        guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
            values.isRegularFile == true, values.isSymbolicLink != true
        else { return nil }
        let ext = resolved.pathExtension.lowercased()
        guard textExtensions.contains(ext), let type = UTType(filenameExtension: ext), type.conforms(to: .plainText),
            !type.conforms(to: .script), !type.conforms(to: .executable)
        else { return nil }
        return resolved
    }

    /// The names a skill's text may have once resolved. A shell script (`.command`, `.sh`) is plain text to
    /// LaunchServices too, so conformance alone would let one through.
    static let textExtensions: Set<String> = ["md", "markdown", "txt"]

    /// What Finder should select for "Open folder": `folder` when it exists, else its nearest existing parent.
    static func revealTarget(_ folder: URL) -> URL {
        var target = folder
        while !FileManager.default.fileExists(atPath: target.path) && target.pathComponents.count > 1 {
            target = target.deletingLastPathComponent()
        }
        return target
    }

    /// A link a package supplied (its repository) opens in the browser only when it is http or https; any other
    /// scheme (`file:`, an app's custom scheme) is shown as text.
    static func isWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return url.host?.isEmpty == false
    }
}
