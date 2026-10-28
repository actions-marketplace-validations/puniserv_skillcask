import Foundation

/// A package spec as `skillcask add` takes it: the three shapes `src/commands.rs` `add` accepts, read once for both
/// places the app takes one as text. The CLI stays the judge of whether the package exists or the policy allows it.
///
/// - `vendor/name[@constraint]`: a registry package (`manifest::valid_package_name`: lowercase, digits, `_.-`
///   inside, no `..`, both parts starting and ending with a letter or digit).
/// - `github:owner/repo[/skill][@version-or-ref]` (`add_github`). `add` takes the skill path, `info` does not (it
///   wants `github:owner/repo`): `infoTarget` drops it.
/// - `git:https://host/owner/repo[.git][@ref]` (`git_spec`, `git::check_url`, `git::name_of`).
///
/// Two readings of the same grammar:
/// - `parse` detects (the Add Skill field, S8: "the field accepts a term or a source"): a registry spec must be
///   valid, anything else without a prefix is a search term; any `github:` or `git:` text is a source, which the
///   CLI judges and explains.
/// - `validate` checks (the Adopt sheet's typed source, S9): syntax as the CLI checks it before resolving anything,
///   so a typo is refused without a round trip, with the `Problem` that says which shape went wrong.
///
/// The scheme prefixes are case-sensitive, as the CLI's `strip_prefix` is: `GitHub:a/b` is a registry name.
public struct PackageSpec: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case registry
        case github
        case git
    }

    /// Why `validate` refuses a typed spec.
    public enum Problem: Error, Hashable, Sendable {
        /// Nothing typed yet.
        case empty
        /// `vendor/name` with an invalid name (`vendor/name, lowercase`), or a constraint that is empty.
        case packageName
        /// `github:` with no valid `owner/repo`, an invalid skill name, or an empty ref.
        case github
        /// `git:` with a URL that is not `https://host/owner/repo` without credentials, query or fragment.
        case gitURL
    }

    public let kind: Kind
    /// The spec without its `@` part: `vendor/name`, `github:owner/repo/skill`, `git:https://…/repo.git` (trailing
    /// `/` dropped, as `git_spec` does).
    public let base: String
    /// The `@constraint` or `@ref` typed, without the `@`; nil when none was typed.
    public let pinned: String?
    /// The name the lock keys the package by: `vendor/name`, `owner/repo` (lowercased, as the CLI does for GitHub
    /// and git sources).
    public let package: String
    /// The one skill a `github:owner/repo/skill` spec selects (skills.sh's result shape); nil otherwise.
    public let skill: String?

    /// The spec as `add` and `info` take it, with the typed `@` part.
    public var text: String {
        pinned.map { "\(base)@\($0)" } ?? base
    }

    /// `text` with `constraint` appended, unless the spec already pinned one (the typed pin wins).
    public func text(constraint: String?) -> String {
        guard pinned == nil, let constraint, !constraint.isEmpty else { return text }
        return "\(base)@\(constraint)"
    }

    /// What `info` takes for this spec: the spec itself, except that a GitHub skill path is dropped
    /// (`github:owner/repo/skill@v1` → `github:owner/repo@v1`), since `info` accepts only `owner/repo`
    /// (`src/commands.rs` `info`).
    public var infoTarget: String {
        guard kind == .github, skill != nil else { return text }
        let target = Self.githubPrefix + package
        return pinned.map { "\(target)@\($0)" } ?? target
    }

    /// The source in `text` (surrounding whitespace ignored), or nil when it is a search term (or empty, or has
    /// whitespace inside).
    public static func parse(_ text: String) -> PackageSpec? {
        read(text).spec
    }

    /// The spec in `text` (surrounding whitespace ignored) when the CLI's syntax checks accept it, else why not.
    public static func validate(_ text: String) -> Result<PackageSpec, Problem> {
        let reading = read(text)
        if let spec = reading.spec, reading.problem == nil {
            return .success(spec)
        }
        return .failure(reading.problem ?? .empty)
    }

    /// The lock name of a search result's `name` (`vendor/name`, or skills.sh's `github:owner/repo/skill`); the
    /// name itself, lowercased, when it has neither shape.
    public static func packageName(of result: String) -> String {
        parse(result)?.package ?? result.lowercased()
    }

    /// `manifest::valid_package_name`.
    public static func isPackageName(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { part in
            guard let first = part.first, let last = part.last else { return false }
            return isLowerAlnum(first) && isLowerAlnum(last)
                && part.allSatisfy { isLowerAlnum($0) || "_.-".contains($0) } && !part.contains("..")
        }
    }

    // MARK: - Shapes

    static let githubPrefix = "github:"
    static let gitPrefix = "git:"
    private static let https = "https://"

    /// One reading of a spec: the source it names, if any, and what the CLI would refuse about it. A registry spec
    /// is a source only when valid; a `github:` or `git:` one is a source whenever its path is not empty.
    private typealias Reading = (spec: PackageSpec?, problem: Problem?)

    private static func read(_ text: String) -> Reading {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, .empty) }
        let whitespace = trimmed.contains(where: \.isWhitespace)
        if trimmed.hasPrefix(githubPrefix) {
            return whitespace ? (nil, .github) : github(String(trimmed.dropFirst(githubPrefix.count)))
        }
        if trimmed.hasPrefix(gitPrefix) {
            return whitespace ? (nil, .gitURL) : git(String(trimmed.dropFirst(gitPrefix.count)))
        }
        let (name, pinned) = split(trimmed, at: trimmed.firstIndex(of: "@"))
        guard !whitespace, isPackageName(name), pinned?.isEmpty != true else { return (nil, .packageName) }
        return (PackageSpec(kind: .registry, base: name, pinned: pinned, package: name, skill: nil), nil)
    }

    /// `add_github`: `owner/repo` lowercased must be a package name, the rest of the path (`splitn(3, '/')`) a
    /// skill name (`skill::valid_name`), the `@` part not empty. `package` is `owner/repo`, lowercased.
    private static func github(_ rest: String) -> Reading {
        let (path, pinned) = split(rest, at: rest.firstIndex(of: "@"))
        guard !path.isEmpty else { return (nil, .github) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let package = parts.prefix(2).joined(separator: "/").lowercased()
        let skill = parts.count > 2 && !parts[2].isEmpty ? parts[2...].joined(separator: "/") : nil
        let spec = PackageSpec(kind: .github, base: githubPrefix + path, pinned: pinned, package: package, skill: skill)
        let skillPath = parts.count > 2 ? parts[2...].joined(separator: "/") : nil
        let valid =
            pinned?.isEmpty != true && parts.count >= 2 && isPackageName(package)
            && skillPath.map(isSkillName) ?? true
        return (spec, valid ? nil : .github)
    }

    /// `git_spec`: the `@` is split off from the end only past the scheme, so an `@` inside `https://` is not a
    /// ref, and trailing `/` are dropped. Then `git::check_url` (https, a host, no credentials, query or fragment,
    /// at least two path segments) and `git::name_of` (the last two segments without `_git` and `.git`,
    /// lowercased, a valid package name). `package` is that name, or the URL lowercased when it has fewer
    /// segments.
    private static func git(_ rest: String) -> Reading {
        let at = rest.lastIndex(of: "@")
            .flatMap { rest.distance(from: rest.startIndex, to: $0) > https.count ? $0 : nil }
        var (url, pinned) = split(rest, at: at)
        while url.hasSuffix("/") {
            url.removeLast()
        }
        guard !url.isEmpty else { return (nil, .gitURL) }
        let afterScheme = url.range(of: "://").map { url[$0.upperBound...] } ?? Substring(url)
        let path = afterScheme.split(separator: "/").dropFirst().filter { $0 != "_git" }.map(String.init)
        let package: String
        if path.count >= 2, let last = path.last {
            let repo = last.hasSuffix(".git") ? String(last.dropLast(4)) : last
            package = "\(path[path.count - 2])/\(repo)".lowercased()
        } else {
            package = url.lowercased()
        }
        let spec = PackageSpec(kind: .git, base: gitPrefix + url, pinned: pinned, package: package, skill: nil)
        let valid = pinned?.isEmpty != true && isCheckedURL(url) && isPackageName(package)
        return (spec, valid ? nil : .gitURL)
    }

    /// `git::check_url`.
    private static func isCheckedURL(_ url: String) -> Bool {
        guard let components = URLComponents(string: url), components.scheme == "https",
            let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil
        else { return false }
        return components.path.split(separator: "/").count >= 2
    }

    private static func split(_ text: String, at index: String.Index?) -> (String, String?) {
        guard let index else { return (text, nil) }
        return (String(text[..<index]), String(text[text.index(after: index)...]))
    }

    /// `skill::valid_name`: `[a-z0-9][a-z0-9-]*`.
    private static func isSkillName(_ name: String) -> Bool {
        guard let first = name.first, isLowerAlnum(first) else { return false }
        return name.allSatisfy { isLowerAlnum($0) || $0 == "-" }
    }

    private static func isLowerAlnum(_ character: Character) -> Bool {
        character.isASCII && (character.isLowercase || character.isNumber)
    }
}
