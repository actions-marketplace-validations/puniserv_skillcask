/// A `major.minor.patch[-prerelease]` version as `skillcask --version` prints it.
public struct Version: Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// `rc1` of `0.10.0-rc1`; a pre-release sorts before the release it precedes.
    public let prerelease: String?

    public init(_ major: Int, _ minor: Int, _ patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// `0.9.1`, `v0.9.1` or `0.10.0-rc1`; nil for anything else.
    public init?(_ text: String) {
        var rest = Substring(text)
        if rest.hasPrefix("v") {
            rest = rest.dropFirst()
        }
        var prerelease: String?
        if let dash = rest.firstIndex(of: "-") {
            prerelease = String(rest[rest.index(after: dash)...])
            rest = rest[..<dash]
        }
        let parts = rest.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let major = parts[0], let minor = parts[1], let patch = parts[2] else { return nil }
        guard major >= 0, minor >= 0, patch >= 0, prerelease?.isEmpty != true else { return nil }
        self.init(major, minor, patch, prerelease: prerelease)
    }

    /// The version in `skillcask 0.9.1 (1afcd7c81d2e)`; nil when the output is not the CLI's.
    public init?(cliOutput: String) {
        let words = cliOutput.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2, words[0] == "skillcask" else { return nil }
        self.init(String(words[1]))
    }
}

extension Version: Comparable {
    public static func < (lhs: Version, rhs: Version) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil), (nil, .some): return false
        case (.some, nil): return true
        case (.some(let left), .some(let right)): return left < right
        }
    }
}

extension Version: CustomStringConvertible {
    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(core)-\($0)" } ?? core
    }
}
