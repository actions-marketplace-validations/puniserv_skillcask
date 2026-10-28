/// The version rule the Add Skill popover writes into the spec (`vendor/name@<constraint>`), which `add` stores in
/// skills.toml (AddSkill board: "Up to next major ^4.2 · Written to skills.toml; skills.lock pins v4.2.0
/// exactly"). Built from the version `info` says would be installed, the same way the CLI builds its default
/// (`default_constraint` in `src/commands.rs`: `^major.minor`, `^0.0.patch`, or the exact version when the policy
/// forbids ranges).
public enum VersionRule: Hashable, Sendable, CaseIterable {
    /// `^4.2`: compatible updates (the CLI's default when ranges are allowed).
    case compatible
    /// `~4.2.0`: patch releases only.
    case patches
    /// `4.2.0`: this version only.
    case exact

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
}
