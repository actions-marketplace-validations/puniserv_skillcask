import SkillcaskCore
import Testing

@testable import SkillcaskDomain

/// Every CLI source string maps to one kind; rows resolve through their `Kind` before their `source`.
@Suite struct SourceKindTests {
    @Test(arguments: [
        ("packagist", SourceKind.packagist), ("composer", .packagist), ("Packagist", .packagist),
        ("github", .github), ("github:anthropics/skills", .github),
        ("git", .git), ("git:https://git.acme.example/sql-review.git", .git), ("git@github.com:a/b.git", .git),
        ("https://git.acme.example/sql-review.git", .git),
        ("skills.sh", .skillsSh), ("skills-sh", .skillsSh),
        ("project", .project), ("local", .local),
        ("acme", .custom("acme")), (" acme ", .custom("acme")), ("Internal Mirror", .custom("Internal Mirror")),
    ])
    func parsesTheCLIStrings(text: String, expected: SourceKind) {
        #expect(SourceKind(parsing: text) == expected)
    }

    @Test func rowKindWinsOverSourceAndAdoptIsParsed() {
        #expect(SourceKind.kind(of: entry(kind: .project, source: "packagist")) == .project)
        #expect(SourceKind.kind(of: entry(kind: .handWritten, source: nil)) == .local)
        let adopted = entry(kind: .notManaged(adopt: "github:juliusbrussee/caveman"), source: nil)
        #expect(SourceKind.kind(of: adopted) == .github)
        #expect(SourceKind.kind(of: entry(kind: .notManaged(adopt: nil), source: nil)) == nil)
        #expect(SourceKind.kind(of: entry(kind: .package("acme/lint"), source: "acme")) == .custom("acme"))
        #expect(SourceKind.kind(of: entry(kind: .dependency("a/b", via: ["c"]), source: nil)) == nil)
    }

    private func entry(kind: SkillEntry.Kind, source: String?) -> SkillEntry {
        SkillEntry(
            id: "x", name: "x", kind: kind, source: source, version: nil, state: .ok, health: .installed,
            update: nil, findings: [], path: nil, description: nil)
    }
}
