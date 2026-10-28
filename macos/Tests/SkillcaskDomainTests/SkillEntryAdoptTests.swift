import SkillcaskCore
import SkillcaskDomain
import Testing

/// The adopt spec of a not managed row, read as a location: only `github:` and `git:` are schemes the CLI
/// accepts (D38), so only those are dropped.
@Suite struct SkillEntryAdoptTests {
    @Test func dropsOnlyTheTwoAdoptSchemes() {
        #expect(SkillEntry.location(ofAdoptSpec: "github:juliusbrussee/caveman") == "juliusbrussee/caveman")
        #expect(
            SkillEntry.location(ofAdoptSpec: "git:https://git.acme.example/sql-review.git")
                == "https://git.acme.example/sql-review.git")
        #expect(
            SkillEntry.location(ofAdoptSpec: " GitHub:anthropics/skills/frontend-design ")
                == "anthropics/skills/frontend-design")
        #expect(SkillEntry.location(ofAdoptSpec: "https://example.com/x.git") == "https://example.com/x.git")
        #expect(SkillEntry.location(ofAdoptSpec: "owner/repo") == "owner/repo")
    }

    @Test func adoptLocationIsOnlyForNotManagedRowsWithASpec() {
        let notManaged = entry(kind: .notManaged(adopt: "github:juliusbrussee/caveman"))
        #expect(notManaged.adoptLocation == "juliusbrussee/caveman")
        #expect(entry(kind: .notManaged(adopt: nil)).adoptLocation == nil)
        #expect(entry(kind: .package("acme/commit")).adoptLocation == nil)
        #expect(entry(kind: .project).adoptLocation == nil)
    }

    private func entry(kind: SkillEntry.Kind) -> SkillEntry {
        SkillEntry(
            id: "x", name: "x", kind: kind, source: nil, version: nil, state: .ok, health: .installed, update: nil,
            findings: [], path: nil, description: nil)
    }
}
