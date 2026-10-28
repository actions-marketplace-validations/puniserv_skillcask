import SkillcaskDomain

/// The single adopt's version rule, as a value: the rules offered, the one shown, the constraint each writes and the
/// spec it builds. No version is known before `add` runs (`status` prints a not managed row without one,
/// `src/commands.rs` 1843–1844), so the rules built from a version are not offered: the CLI's default ("As the
/// command-line tool chooses", writing nothing, so `add` picks `^major.minor` of what it installs), Latest (`*`), and
/// Branch for a GitHub or git source. All three need `allow-ranges`; without it the row is hidden and the CLI pins
/// the exact version it installs.
struct AdoptRule {
    /// Always nil: the rules never name a span.
    let base: VersionRule.Base? = nil
    let options: [VersionRule]
    let effective: VersionRule
    private let pinned: Bool

    init(spec: PackageSpec?, allowRanges: Bool, chosen: VersionRule?, branch: String) {
        pinned = spec?.pinned != nil
        options =
            spec == nil || !allowRanges
            ? [] : VersionRule.options(for: nil, allowRanges: true, source: spec?.kind, branch: branch)
        if case .branch = chosen {
            effective = .branch(branch)
        } else {
            effective = chosen ?? .compatible
        }
    }

    /// A source that is valid and pins nothing, with a choice to make.
    var isShown: Bool {
        !pinned && options.count > 1
    }

    /// What `rule` writes: nothing for the CLI's default, `*` for Latest, the branch name for Branch.
    func constraint(of rule: VersionRule) -> String? {
        rule.constraint(base: nil)
    }

    /// The Branch rule with an empty name or one the CLI would refuse or read as a version.
    var hasProblem: Bool {
        guard isShown, case .branch(let name) = effective else { return false }
        return !VersionRule.isValidBranch(name)
    }

    /// `spec` with `@<constraint>` for a chosen rule (`github:juliusbrussee/caveman@*`); unchanged otherwise.
    func specText(_ spec: String) -> String {
        guard isShown, let constraint = constraint(of: effective), let parsed = PackageSpec.parse(spec) else {
            return spec
        }
        return parsed.text(constraint: constraint)
    }
}
