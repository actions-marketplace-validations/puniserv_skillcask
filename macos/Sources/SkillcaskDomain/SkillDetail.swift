import SkillcaskCore

/// What the detail column loads for the selected row beyond its `SkillEntry`: the offline `info --json <skill>`
/// document and the skill's SKILL.md. Either half may be missing: a not managed skill has no info document, a
/// package that is not installed has no file. The errors are kept so the tabs can say why a half is absent.
public struct SkillDetail: Hashable, Sendable {
    /// `info --json <skill>`; nil for a not managed skill or when it failed (`infoError`).
    public let info: InfoDocument?
    /// The skill's SKILL.md; nil when the row has no path or the file could not be read (`textError`).
    public let text: SkillText?
    /// Why `info` is nil when the CLI was asked and could not answer; nil when it was not asked.
    public let infoError: CLIError?
    /// Why `text` is nil: the file is missing, unreadable, or the row has no path.
    public let textError: String?

    public init(info: InfoDocument? = nil, text: SkillText? = nil, infoError: CLIError? = nil, textError: String? = nil)
    {
        self.info = info
        self.text = text
        self.infoError = infoError
        self.textError = textError
    }
}
