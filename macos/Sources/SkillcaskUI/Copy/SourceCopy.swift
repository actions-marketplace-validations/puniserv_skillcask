import SkillcaskDomain

/// What a source pill says, verbatim from the Components board ("Source pill": icon + name; custom
/// repositories show their configured name).
public enum SourceCopy {
    /// The pill text of a source.
    public static func label(_ source: SourceKind) -> String {
        switch source {
        case .packagist: "Packagist"
        case .github: "GitHub"
        case .git: "Git"
        case .skillsSh: "skills.sh"
        case .custom(let name): name
        case .project: "Project"
        case .local: "Local"
        }
    }

    /// The pill text of a source the policy blocks: "GitHub · blocked".
    public static func blocked(_ source: SourceKind) -> String {
        "\(label(source)) · blocked"
    }
}
