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
        let skillPath = parts.count > 2 ? parts[2...].joined(separator: "/") : nil
        let skill = parts.count > 2 && !parts[2].isEmpty ? skillPath : nil
        let spec = PackageSpec(kind: .github, base: githubPrefix + path, pinned: pinned, package: package, skill: skill)
        let valid =
            pinned?.isEmpty != true && parts.count >= 2 && isPackageName(package)
            && skillPath.map(isSkillName) ?? true
        return (spec, valid ? nil : .github)
    }

    /// `git_spec`: the `@` is split off from the end only past the scheme, so an `@` inside `https://` is not a
    /// ref, and trailing `/` are dropped. Then `git::check_url` (https, a host, no credentials, query or fragment,
    /// at least two path segments) and `git::name_of` (the last two segments without `_git` and `.git`,
    /// lowercased, a valid package name), both over the URL as `url::Url::parse` reads it (`HTTPSURL`). `package`
    /// is that name, or the URL lowercased when it has fewer segments. `base` keeps the URL as typed, as the CLI
    /// writes it to the manifest.
    private static func git(_ rest: String) -> Reading {
        let at = rest.lastIndex(of: "@")
            .flatMap { rest.distance(from: rest.startIndex, to: $0) > https.count ? $0 : nil }
        var (url, pinned) = split(rest, at: at)
        while url.hasSuffix("/") {
            url.removeLast()
        }
        guard !url.isEmpty else { return (nil, .gitURL) }
        let parsed = HTTPSURL(url)
        let path = parsed?.segments.filter { !$0.isEmpty && $0 != "_git" } ?? []
        let package: String
        if path.count >= 2, let last = path.last {
            let repo = last.hasSuffix(".git") ? String(last.dropLast(4)) : last
            package = "\(path[path.count - 2])/\(repo)".lowercased()
        } else {
            package = url.lowercased()
        }
        let spec = PackageSpec(kind: .git, base: gitPrefix + url, pinned: pinned, package: package, skill: nil)
        let valid = pinned?.isEmpty != true && parsed?.isChecked == true && isPackageName(package)
        return (spec, valid ? nil : .gitURL)
    }

    /// An `https:` URL as `url::Url::parse` (WHATWG, a special scheme) reads it, enough for `check_url` and
    /// `name_of`: the scheme in any case, any run of `/` or `\` after `https:`, `\` read as `/`, `.` and `..`
    /// segments (also `%2e`, any case) resolved, an empty userinfo (`https://@host`) dropped. The host: a port is
    /// digits up to 65535 (empty is none), a bracketed host must be IPv6, a host whose last label is a number
    /// must be an IPv4 address (`0x`, octal and short forms included), and a percent-encoded host is refused.
    /// Credentials and the remaining host characters are left to `URLComponents` on the rebuilt URL.
    ///
    /// Not mirrored, where the app and the CLI can differ:
    /// - IDNA: `url` maps `bücher.example` to punycode and refuses bad punycode (`xn--abc`); here
    ///   `URLComponents` decides.
    /// - Percent-encoded hosts: `url` decodes them (`ho%41st` is `hoast`, accepted; `ho%00st` refused); here any
    ///   `%` in the host is refused.
    /// - Tab, newline and surrounding spaces, which `url` strips: the app refuses whitespace in a spec first.
    /// - The percent-encoding `url` adds to path characters such as `{`: refused both here and by `name_of`,
    ///   whose name would hold a `%`.
    private struct HTTPSURL {
        let authority: String
        /// The path segments after dot-segment resolution; empty ones kept (both CLI checks skip them).
        let segments: [String]
        /// `?…` or `#…` as typed, or empty.
        let tail: String

        init?(_ url: String) {
            let scheme = "https:"
            guard url.lowercased().hasPrefix(scheme) else { return nil }
            var rest = Substring(url.dropFirst(scheme.count))
            let end = rest.firstIndex { $0 == "?" || $0 == "#" } ?? rest.endIndex
            tail = String(rest[end...])
            rest = Substring(rest[..<end].replacingOccurrences(of: "\\", with: "/"))
            rest = rest.drop { $0 == "/" }
            let slash = rest.firstIndex(of: "/") ?? rest.endIndex
            var authority = String(rest[..<slash])
            if authority.hasPrefix("@"), authority.dropFirst().contains("@") == false {
                authority.removeFirst()
            }
            self.authority = authority
            var segments: [String] = []
            for segment in rest[slash...].split(separator: "/", omittingEmptySubsequences: false).dropFirst() {
                switch segment.lowercased().replacingOccurrences(of: "%2e", with: ".") {
                case ".": continue
                case "..": _ = segments.popLast()
                default: segments.append(String(segment))
                }
            }
            self.segments = segments
        }

        /// `git::check_url` on the URL as read.
        var isChecked: Bool {
            guard let authority = Self.checkedAuthority(authority) else { return false }
            let rebuilt = "https://\(authority)/\(segments.joined(separator: "/"))\(tail)"
            guard let components = URLComponents(string: rebuilt), let host = components.host, !host.isEmpty,
                components.user == nil, components.password == nil, components.query == nil,
                components.fragment == nil
            else { return false }
            return segments.filter { !$0.isEmpty }.count >= 2
        }

        /// `authority` with its port normalised (an empty port dropped), or nil when `url`'s host or port parser
        /// refuses it.
        private static func checkedAuthority(_ authority: String) -> String? {
            let at = authority.lastIndex(of: "@")
            let userinfo = at.map { String(authority[...$0]) } ?? ""
            let hostPort = at.map { authority[authority.index(after: $0)...] } ?? Substring(authority)
            let host: Substring
            let port: Substring?
            if hostPort.hasPrefix("[") {
                guard let close = hostPort.firstIndex(of: "]") else { return nil }
                host = hostPort[...close]
                let after = hostPort[hostPort.index(after: close)...]
                guard after.isEmpty || after.hasPrefix(":") else { return nil }
                port = after.isEmpty ? nil : after.dropFirst()
                guard isIPv6(String(host.dropFirst().dropLast())) else { return nil }
            } else {
                let colon = hostPort.firstIndex(of: ":")
                host = colon.map { hostPort[..<$0] } ?? hostPort
                port = colon.map { hostPort[hostPort.index(after: $0)...] }
                guard !host.isEmpty, !host.contains("%") else { return nil }
                if endsInANumber(host), ipv4(host) == nil { return nil }
            }
            guard let port, !port.isEmpty else { return userinfo + host }
            let significant = port.drop { $0 == "0" }
            guard port.allSatisfy(isDigit), significant.count <= 5,
                let number = Int(significant.isEmpty ? "0" : significant),
                number <= 65535
            else { return nil }
            return "\(userinfo)\(host):\(number)"
        }

        /// WHATWG "ends in a number": the last label (a trailing empty one skipped) is digits or an IPv4 number.
        private static func endsInANumber(_ host: Substring) -> Bool {
            var labels = host.split(separator: ".", omittingEmptySubsequences: false)
            if labels.last?.isEmpty == true {
                guard labels.count > 1 else { return false }
                labels.removeLast()
            }
            guard let last = labels.last else { return false }
            return (!last.isEmpty && last.allSatisfy(isDigit)) || ipv4Number(last) != nil
        }

        /// The WHATWG IPv4 parser: up to four numbers (a trailing empty label skipped), each part but the last
        /// at most 255, the last filling the bytes left.
        private static func ipv4(_ host: Substring) -> UInt64? {
            var labels = host.split(separator: ".", omittingEmptySubsequences: false)
            if labels.last?.isEmpty == true, labels.count > 1 {
                labels.removeLast()
            }
            guard labels.count <= 4 else { return nil }
            let numbers = labels.map(ipv4Number)
            guard let last = numbers.last, let last else { return nil }
            let head = numbers.dropLast()
            guard head.allSatisfy({ ($0 ?? 256) <= 255 }) else { return nil }
            let limit = UInt64(1) << (8 * UInt64(5 - numbers.count))
            guard last < limit else { return nil }
            return head.enumerated().reduce(last) { $0 + ($1.element ?? 0) << (8 * UInt64(3 - $1.offset)) }
        }

        /// The WHATWG IPv4 number parser: `0x`/`0X` hex, a leading `0` octal, else decimal; an empty part
        /// fails, a bare prefix is 0. Values past `UInt64` fail (they are past every limit anyway).
        private static func ipv4Number(_ part: Substring) -> UInt64? {
            guard !part.isEmpty else { return nil }
            var digits = part
            var radix = 10
            if digits.hasPrefix("0x") || digits.hasPrefix("0X") {
                digits = digits.dropFirst(2)
                radix = 16
            } else if digits.count >= 2, digits.hasPrefix("0") {
                digits = digits.dropFirst()
                radix = 8
            }
            guard !digits.isEmpty else { return 0 }
            guard digits.allSatisfy(\.isASCII) else { return nil }
            return UInt64(digits, radix: radix)
        }

        private static func isDigit(_ character: Character) -> Bool {
            character.isASCII && character.isNumber
        }

        /// The address inside `[…]`, as the WHATWG IPv6 parser accepts it (`inet_pton` agrees on every form a
        /// git host uses).
        private static func isIPv6(_ address: String) -> Bool {
            var storage = in6_addr()
            return inet_pton(AF_INET6, address, &storage) == 1
        }
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
