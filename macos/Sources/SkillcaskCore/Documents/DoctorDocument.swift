/// `doctor --json` (D32): link, git-index and gitignore checks. Exit 1 with this document when `problems` is not
/// empty; `--fix` moves what it repaired into `fixed`.
public struct DoctorDocument: Decodable, Hashable, Sendable {
    public let ok: Bool
    public let passed: [String]
    public let problems: [String]
    public let fixed: [String]
    public let warnings: [String]
}
