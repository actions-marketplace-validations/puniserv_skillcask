/// The version rule the Add Skill popover writes into the spec (`vendor/name@<constraint>`), which `add` stores in
/// skills.toml (AddSkill board: "Up to next major ^4.2 · Written to skills.toml; skills.lock pins v4.2.0
/// exactly"). Built from the version `info` says would be installed, the same way the CLI builds its default
/// (`default_constraint` in `src/commands.rs`: `^major.minor`, `^0.0.patch`, or the exact version when the policy
/// forbids ranges).
///
/// Flow-F2's popover offers "Up to next major (default) / Exact / Latest / Branch"; each is offered only where the
/// CLI accepts what it writes (`options(for:allowRanges:source:branch:)`).
public enum VersionRule: Hashable, Sendable {
    /// `^4.2`: compatible updates (the CLI's default when ranges are allowed).
    case compatible
    /// `~4.2.0`: patch releases only.
    case patches
    /// `4.2.0`: this version only.
    case exact
    /// `*`: the newest version, whatever its major (Composer's any-version constraint).
    case latest
    /// A git ref of a GitHub or git source (`github:owner/repo@main`): `add_github` and `add_git` take an `@` part
    /// that is not a version constraint as a ref (`GitHub::Ref`, `src/commands.rs` 1389–1400) and keep following
    /// it; skills.lock pins its current commit.
    case branch(String)

    /// A `major.minor.patch` version read from `info`'s `version` (a leading `v` and a pre-release or build
    /// suffix are tolerated); nil for a git ref such as `main`, which gets no rule.
    public struct Base: Hashable, Sendable {
        public let major: Int
        public let minor: Int
        public let patch: Int
        /// The version as `info` printed it, without a leading `v`: `4.2.0`, `4.2.0.1`, `1.0.0-beta.2`; a one- or
        /// two-part version padded to three (`1.2` → `1.2.0`).
        public let text: String

        public init?(_ text: String) {
            var core = Substring(text)
            if core.first == "v" || core.first == "V" {
                core = core.dropFirst()
            }
            let suffix = core.drop { $0 != "-" && $0 != "+" }
            core = core.prefix { $0 != "-" && $0 != "+" }
            let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
            guard (1...4).contains(numbers.count), let major = numbers[0] else { return nil }
            let rest = numbers.dropFirst()
            guard rest.allSatisfy({ $0 != nil }) else { return nil }
            self.major = major
            minor = numbers.count > 1 ? numbers[1] ?? 0 : 0
            patch = numbers.count > 2 ? numbers[2] ?? 0 : 0
            // `is_exact` needs three parts: `1.2` is written `1.2.0`, as `default_constraint` does.
            self.text = (numbers.count < 3 ? "\(major).\(minor).\(patch)" : String(core)) + suffix
        }

        /// The exact constraint: the version verbatim, pre-release and fourth part included, as the CLI's
        /// `default_constraint` keeps an exact version (`is_exact`).
        public var exact: String {
            text
        }

        /// `major.minor.patch`, for `~`.
        var triple: String {
            "\(major).\(minor).\(patch)"
        }
    }

    /// The constraint this rule writes for `base`.
    public func constraint(for base: Base) -> String {
        switch self {
        case .compatible:
            base.major == 0 && base.minor == 0 ? "^0.0.\(base.patch)" : "^\(base.major).\(base.minor)"
        case .patches:
            "~\(base.triple)"
        case .exact:
            base.exact
        case .latest:
            "*"
        case .branch(let ref):
            ref
        }
    }

    /// The constraint when the version `add` would install may be unknown (the Adopt sheet knows only the copy's
    /// version): nil for a rule built from a version when `base` is nil.
    public func constraint(base: Base?) -> String? {
        if let base {
            return constraint(for: base)
        }
        switch self {
        case .latest: return "*"
        case .branch(let ref): return ref
        case .compatible, .patches, .exact: return nil
        }
    }

    /// What the CLI writes when no rule is given: `^major.minor` with ranges allowed, else the exact version.
    public static func cliDefault(allowRanges: Bool) -> VersionRule {
        allowRanges ? .compatible : .exact
    }

    /// The rules the popover offers: only `.exact` when `policy.allow-ranges = false` (the CLI refuses a range
    /// then), and no `.patches` for a `0.x` version, where `^0.y` already stops at the next minor.
    public static func options(for base: Base, allowRanges: Bool) -> [VersionRule] {
        guard allowRanges else { return [.exact] }
        return base.major == 0 ? [.compatible, .exact] : [.compatible, .patches, .exact]
    }

    /// Flow-F2's full list for a spec of `source`: the version rules above when `base` is known (only the CLI's
    /// default `.compatible` without one, which writes nothing), then `.latest` (`*`) and, for a GitHub or git
    /// source, `.branch(branch)`. Both need `allow-ranges`: the CLI refuses `*` (`is_exact`) and any ref but a full
    /// commit sha (`manifest::check_constraint`) when the policy forbids ranges.
    public static func options(
        for base: Base?, allowRanges: Bool, source: PackageSpec.Kind?, branch: String
    ) -> [VersionRule] {
        // Not named `options`: Swift 6.3 resolves that name inside its own initializer to the local variable.
        var rules: [VersionRule] =
            base.map { Self.options(for: $0, allowRanges: allowRanges) } ?? (allowRanges ? [.compatible] : [])
        guard allowRanges else { return rules }
        rules.append(.latest)
        if let source, source != .registry {
            rules.append(.branch(branch))
        }
        return rules
    }

    /// Whether `ref` is a branch name `add` takes as a ref, as the CLI decides: `manifest::check_constraint`'s ref
    /// rule (ASCII letters, digits, `._/-`; no leading `-` or `/`, no trailing `/`, no `..` or `//`) and not
    /// something `Constraint::parse` reads as a version first (`add_github`, `src/commands.rs` 1389–1400: a parsable
    /// `@` part is a tag constraint). Within those characters a constraint is one bare atom (`src/version.rs`
    /// `atom`): `x`/`X`, `<version>.x`, or a version (`parse_partial`). So `2024-release` and `release-1` are refs,
    /// `1.0`, `v2`, `1.x` and `2-beta1` are versions.
    public static func isValidBranch(_ ref: String) -> Bool {
        guard !ref.isEmpty, !ref.hasPrefix("-"), !ref.hasPrefix("/"), !ref.hasSuffix("/"), !ref.contains(".."),
            !ref.contains("//"),
            ref.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._/-".contains($0)) })
        else { return false }
        return !readsAsVersion(ref)
    }

    /// `Constraint::parse` accepts `atom` (a single token without an operator, as these characters allow).
    static func readsAsVersion(_ atom: String) -> Bool {
        if atom == "x" || atom == "X" {
            return true
        }
        for suffix in [".x", ".X"] where atom.hasSuffix(suffix) {
            // `strip_suffix` matched: a version prefix without a stability word, else no constraint at all.
            return partialVersion(String(atom.dropLast(2))).map { !$0 } ?? false
        }
        return partialVersion(atom) != nil
    }

    /// `src/version.rs` `parse_partial` for the ref characters: nil when `text` is not a version, else whether a
    /// stability suffix was written.
    static func partialVersion(_ text: String) -> Bool? {
        var rest = Substring(text)
        if rest.first == "v" || rest.first == "V" {
            rest = rest.dropFirst()
        }
        if rest.hasPrefix("dev-") {
            return nil
        }
        var count = 0
        while count < 4 {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }.count
            guard digits > 0, digits <= 18 else { break }
            count += 1
            rest = rest.dropFirst(digits)
            guard rest.first == ".", let next = rest.dropFirst().first, next.isASCII, next.isNumber else { break }
            rest = rest.dropFirst()
        }
        guard count > 0 else { return nil }
        rest = rest.drop { ".-_".contains($0) }
        if rest.isEmpty {
            return false
        }
        var body = rest.lowercased()[...]
        var dev = false
        if body.hasSuffix("dev") {
            body = body.dropLast(3)
            while let last = body.last, ".-".contains(last) {
                body = body.dropLast()
            }
            dev = true
        }
        if body.isEmpty {
            return dev ? true : nil
        }
        let word = body.prefix { $0.isASCII && $0.isLetter }
        guard Self.stabilities.contains(String(word)) else { return nil }
        let tail = body.dropFirst(word.count).drop { ".-".contains($0) }
        guard tail.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "." || $0 == "-" }) else { return nil }
        // Each number must parse as a `u64`, as `x.parse().ok()` does.
        guard tail.split(whereSeparator: { $0 == "." || $0 == "-" }).allSatisfy({ UInt64(String($0)) != nil }) else {
            return nil
        }
        return true
    }

    /// `Stability::parse`'s words.
    static let stabilities: Set<String> = ["dev", "alpha", "a", "beta", "b", "rc", "stable", "patch", "pl", "p"]
}
