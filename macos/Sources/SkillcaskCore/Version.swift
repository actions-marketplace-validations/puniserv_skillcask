/// A `major.minor.patch[-prerelease]` version as `skillcask --version` prints it.
public struct Version: Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// `rc.1` of `0.10.1-rc.1`; a pre-release sorts before the release it precedes, by SemVer 2.0 §11 precedence.
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

    /// Exactly `^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$` in ASCII, as `self-check` (D51) reads the cask: no `v`, no
    /// sign, no `+build`, no whitespace; nil for anything else, and for a number too large for `Int`. For versions
    /// that come from the network, where the lenient `init?(_:)` would let `+1` or a `v` through.
    public init?(strict text: String) {
        let (core, prerelease): (Substring, Substring?) =
            if let dash = text.firstIndex(of: "-") {
                (text[..<dash], text[text.index(after: dash)...])
            } else {
                (Substring(text), nil)
            }
        let isDigit = { (byte: UInt8) in (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy(isDigit) }) else { return nil }
        if let prerelease {
            let allowed = { (byte: UInt8) in
                isDigit(byte) || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                    || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) || byte == UInt8(ascii: ".")
                    || byte == UInt8(ascii: "-")
            }
            guard !prerelease.isEmpty, prerelease.utf8.allSatisfy(allowed) else { return nil }
        }
        guard let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        self.init(major, minor, patch, prerelease: prerelease.map(String.init))
    }

    /// Whether `description` reads back through `init?(strict:)`: false for a value built with a prerelease the
    /// cask could not hold (`rc_1`, empty).
    public var isStrict: Bool {
        Version(strict: description) == self
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
        case (.some(let left), .some(let right)): return precedes(left, right)
        }
    }

    /// SemVer 2.0 §11.4: identifiers split on `.`, numeric ones compared as numbers and before alphanumeric ones,
    /// alphanumeric ones in ASCII order, and a longer set after its own prefix. An identifier with a leading zero is
    /// not a SemVer number, so it compares as text: `rc.01` and `rc.1` then differ in `<` as they do in `==`.
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: ".", omittingEmptySubsequences: false)
        let right = rhs.split(separator: ".", omittingEmptySubsequences: false)
        for (a, b) in zip(left, right) where a != b {
            switch (number(a), number(b)) {
            case (let x?, let y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return Array(a.utf8).lexicographicallyPrecedes(Array(b.utf8))
            }
        }
        return left.count < right.count
    }

    private static func number(_ identifier: Substring) -> UInt64? {
        guard identifier == "0" || identifier.first != "0" else { return nil }
        guard !identifier.isEmpty, identifier.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) })
        else { return nil }
        return UInt64(identifier)
    }
}

extension Version: CustomStringConvertible {
    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(core)-\($0)" } ?? core
    }
}
