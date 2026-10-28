import SkillcaskCore

/// What a mutation changed, for the outcome toast and the post-mutation selection. From the planned JSON
/// document when the CLI has it, else from the verb lines the CLI prints (`src/ui.rs` `done`): `added`,
/// `installed`, `updated a -> b`, `locked`, `removed`, `kept … as a dependency`, `adopted`, `created`.
public struct MutationReport: Hashable, Sendable {
    public struct Updated: Hashable, Sendable {
        public let package: String
        public let from: String
        public let to: String
    }

    public var added: [String] = []
    public var installed: [String] = []
    public var updated: [Updated] = []
    public var locked: [String] = []
    public var removed: [String] = []
    public var kept: [String] = []
    public var adopted: [String] = []
    public var created: [String] = []
    public var warnings: [String] = []

    public init() {}

    public init(_ document: MutationDocument, warnings: [String] = []) {
        added = document.added
        installed = document.installed
        updated = document.updated.compactMap(Self.updatedLine)
        removed = document.removed
        self.warnings = document.warnings + warnings
    }

    /// `stdout` lines of a mutation without `--json`; `stderr` warnings come from the `StderrReport`.
    public init(verbLines stdout: String, warnings: [String] = []) {
        self.warnings = warnings
        for raw in stdout.split(separator: "\n") {
            let line = String(raw)
            guard let space = line.firstIndex(of: " ") else { continue }
            let rest = String(line[line.index(after: space)...])
            switch line[..<space] {
            case "added": added.append(Self.firstWord(rest))
            case "installed": installed.append(Self.firstWord(rest))
            case "updated":
                if let updated = Self.updatedLine(rest) {
                    self.updated.append(updated)
                }
            case "locked": locked.append(Self.firstWord(rest))
            case "removed": removed.append(Self.firstWord(rest))
            case "kept": kept.append(Self.firstWord(rest))
            case "adopted": adopted.append(Self.firstWord(rest))
            case "created": created.append(rest)
            default: break
            }
        }
    }

    public var isEmpty: Bool {
        added.isEmpty && installed.isEmpty && updated.isEmpty && locked.isEmpty && removed.isEmpty && kept.isEmpty
            && adopted.isEmpty && created.isEmpty
    }

    /// `acme/one 1.0.0 -> 1.1.0` (also with a leading package name in a JSON document).
    static func updatedLine(_ text: String) -> Updated? {
        let words = text.split(separator: " ").map(String.init)
        guard words.count == 4, words[2] == "->" else { return nil }
        return Updated(package: words[0], from: words[1], to: words[3])
    }

    static func firstWord(_ text: String) -> String {
        String(text.prefix { !$0.isWhitespace && $0 != ":" })
    }
}
