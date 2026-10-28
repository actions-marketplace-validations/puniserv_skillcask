import SkillcaskDomain
import Testing

@testable import SkillcaskUI

/// The S2 trailing-slot rule, the second line per kind and the row copy, each pinned to the boards' rows over the
/// design fixtures. Health itself is Domain's (`HealthMappingTests`); the words are `LabelsTests`.
@Suite struct SkillRowTests {
    // MARK: - Trailing slot

    /// The Main board's rows: exactly one thing each.
    static let trailing: [(String, SkillEntry, SkillRowTrailing)] = [
        ("pdf", DesignFixtures.pdf, .update(to: "1.4.0")),
        ("review-pr", DesignFixtures.reviewPr, .update(to: "2.2.0")),
        ("my-notes", DesignFixtures.myNotes, .findings(2)),
        ("jira-syntax", DesignFixtures.jiraSyntax, .state(.notInstalled)),
        (
            "jira-communication", DesignFixtures.jiraCommunication,
            .state(.cooldown(until: "4.3.0 eligible 2026-10-30T09:14:00Z"))
        ),
        ("deploy-checklist", DesignFixtures.deployChecklist, .state(.changedOnDisk)),
        ("caveman", DesignFixtures.caveman, .state(.notManaged)),
        ("safe-refactor", DesignFixtures.safeRefactor, .dependency),
        ("legacy-lint", DesignFixtures.legacyLint, .state(.unknown("abandoned"))),
        ("test-writer", DesignFixtures.testWriter, .state(.unknown("blocked by policy"))),
        ("commit-message", DesignFixtures.commitMessage, .state(.installed)),
        ("standup-summary", DesignFixtures.standupSummary, .findings(1)),
        ("my-notes, clean audit", projectSkill, .state(.projectSkill)),
    ]

    /// my-notes with a clean audit: the board's quiet "Project skill" row.
    static let projectSkill = SkillEntry(
        id: DesignFixtures.myNotes.id, name: DesignFixtures.myNotes.name, kind: .project, source: nil, version: nil,
        state: .project, health: .projectSkill, update: nil, findings: [], path: DesignFixtures.myNotes.path,
        description: DesignFixtures.myNotes.description)

    @Test(arguments: trailing)
    func trailingShowsExactlyOneThing(name: String, entry: SkillEntry, expected: SkillRowTrailing) {
        #expect(SkillRowTrailing.resolve(entry) == expected, "\(name)")
    }

    @Test func offlineHidesWhatOnlyOutdatedKnows() {
        #expect(SkillRowTrailing.resolve(DesignFixtures.pdf, offline: true) == .state(.installed))
        #expect(SkillRowTrailing.resolve(DesignFixtures.jiraCommunication, offline: true) == .state(.installed))
        #expect(SkillRowTrailing.resolve(DesignFixtures.myNotes, offline: true) == .findings(2))
        #expect(SkillRowTrailing.resolve(DesignFixtures.jiraSyntax, offline: true) == .state(.notInstalled))
        #expect(SkillRowTrailing.resolve(DesignFixtures.deployChecklist, offline: true) == .state(.changedOnDisk))
        #expect(SkillRowTrailing.resolve(DesignFixtures.safeRefactor, offline: true) == .dependency)
        for entry in DesignFixtures.apiOffline.entries {
            #expect(SkillRowTrailing.resolve(entry, offline: true) == SkillRowTrailing.resolve(entry), "\(entry.name)")
        }
    }

    @Test func aPendingUpdateNeverOutranksAWorseState() {
        #expect(DesignFixtures.testWriter.hasUpdate)
        #expect(SkillRowTrailing.resolve(DesignFixtures.testWriter) == .state(.unknown("blocked by policy")))
    }

    @Test func trailingWordsAndColours() {
        #expect(SkillRowTrailing.update(to: "1.4.0").label == "→ 1.4.0")
        #expect(SkillRowTrailing.update(to: "1.4.0").severity == .update)
        #expect(SkillRowTrailing.findings(2).label == "2 findings")
        #expect(SkillRowTrailing.findings(1).label == "1 finding")
        #expect(SkillRowTrailing.findings(2).severity == .warning)
        #expect(SkillRowTrailing.dependency.label == "Dependency")
        #expect(SkillRowTrailing.dependency.severity == .neutral)
        #expect(SkillRowTrailing.state(.installed).label == "Installed")
        #expect(SkillRowTrailing.state(.projectSkill).label == "Project skill")
        #expect(SkillRowTrailing.state(.projectSkill).severity == .ok)
        #expect(SkillRowTrailing.state(.changedOnDisk).severity == .error)
        #expect(
            SkillRowTrailing.state(.cooldown(until: "4.3.0 eligible 2026-10-30T09:14:00Z")).label == "4.3.0 on 30 Oct")
    }

    @Test func onlyOkAndNeutralRowsAreQuiet() {
        #expect(SkillRowTrailing.state(.installed).isQuiet)
        #expect(SkillRowTrailing.state(.projectSkill).isQuiet)
        #expect(SkillRowTrailing.dependency.isQuiet)
        #expect(!SkillRowTrailing.update(to: "1.4.0").isQuiet)
        #expect(!SkillRowTrailing.findings(2).isQuiet)
        #expect(!SkillRowTrailing.state(.notManaged).isQuiet)
        #expect(!SkillRowTrailing.state(.notInstalled).isQuiet)
    }

    // MARK: - Second line

    /// The Main board's second lines, as `List-States` writes them in text.
    static let secondary: [(String, SkillEntry, String)] = [
        ("pdf", DesignFixtures.pdf, "anthropics/skills · GitHub"),
        ("jira-syntax", DesignFixtures.jiraSyntax, "netresearch/agent-jira-skill · Packagist"),
        ("deploy-checklist", DesignFixtures.deployChecklist, ".claude/skills/deploy-checklist · Local"),
        ("sql-review", DesignFixtures.sqlReview, "acme/sql-review · Git"),
        ("my-notes", DesignFixtures.myNotes, ".skills/my-notes · Project"),
        ("caveman", DesignFixtures.caveman, "juliusbrussee/caveman · GitHub"),
        ("legacy-lint", DesignFixtures.legacyLint, "acme/lint · acme"),
        ("standup-summary", DesignFixtures.standupSummary, ".claude/skills/standup-summary"),
    ]

    @Test(arguments: secondary)
    func secondLineNamesTheSource(name: String, entry: SkillEntry, expected: String) {
        #expect(SkillRowSecondary.resolve(entry).text == expected, "\(name)")
    }

    /// The board's "Required by caveman" comes from the snapshot's requirer skills; without them the `via` package
    /// names stand in (Q10 interim), and an empty list counts as none.
    @Test func dependencyNamesTheSkillsThatRequireIt() {
        let requirers = DesignFixtures.api.requirerSkills(of: DesignFixtures.safeRefactor)
        #expect(requirers == ["caveman"])
        #expect(
            SkillRowSecondary.resolve(DesignFixtures.safeRefactor, requiredBy: requirers).text == "Required by caveman")
        #expect(
            SkillRowSecondary.resolve(DesignFixtures.safeRefactor).text == "Required by juliusbrussee/caveman")
        #expect(
            SkillRowSecondary.resolve(DesignFixtures.safeRefactor, requiredBy: []).text
                == "Required by juliusbrussee/caveman")
        #expect(SkillRowSecondary.resolve(DesignFixtures.pdf, requiredBy: ["x"]).text == "anthropics/skills · GitHub")
    }

    @Test func secondLineModelPerKind() {
        #expect(SkillRowSecondary.resolve(DesignFixtures.pdf) == .location("anthropics/skills", source: .github))
        #expect(SkillRowSecondary.resolve(DesignFixtures.myNotes) == .location(".skills/my-notes", source: .project))
        #expect(
            SkillRowSecondary.resolve(DesignFixtures.deployChecklist)
                == .location(".claude/skills/deploy-checklist", source: .local))
        #expect(
            SkillRowSecondary.resolve(DesignFixtures.caveman) == .location("juliusbrussee/caveman", source: .github))
        #expect(SkillRowSecondary.resolve(DesignFixtures.safeRefactor) == .requiredBy(["juliusbrussee/caveman"]))
        #expect(SkillRowSecondary.resolve(Self.projectSkill) == .location(".skills/my-notes", source: .project))
        #expect(
            SkillRowSecondary.resolve(DesignFixtures.standupSummary)
                == .location(".claude/skills/standup-summary", source: nil))
    }

    // MARK: - Copy and metrics

    @Test func rowCopyMatchesTheBoard() {
        #expect(RowCopy.separator == " · ")
        #expect(RowCopy.arrow(to: "1.4.0") == "→ 1.4.0")
        #expect(RowCopy.dependency == "Dependency")
        #expect(RowCopy.secondary(location: "acme/commit", source: .packagist) == "acme/commit · Packagist")
        #expect(RowCopy.secondary(location: nil, source: .project) == "Project")
        #expect(RowCopy.secondary(location: ".skills/x", source: nil) == ".skills/x")
        #expect(RowCopy.secondary(location: nil, source: nil) == "")
    }

    @Test func rowIsTheBoardHeight() {
        #expect(SkillRow.height == Size.row)
        #expect(SkillRow.height == 52)
        #expect(SkillRow.staleOpacity == 0.5)
        #expect(SkillRow.leadingPadding == 14)
        #expect(SkillRow.trailingPadding == 12)
    }
}
