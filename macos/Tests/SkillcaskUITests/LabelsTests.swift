import Foundation
import SkillcaskDomain
import Testing

@testable import SkillcaskUI

/// `Labels` says exactly what the brief (§8) and the Tokens board say, for every `Health` case, and the sort
/// order of the vocabulary is `Severity`'s own.
@Suite struct LabelsTests {
    /// Every `Health` case once, with the board's words.
    static let healthLabels: [(Health, String)] = [
        (.installed, "Installed"),
        (.projectSkill, "Project skill"),
        (.localSkill, "Local skill"),
        (.updateAvailable(from: "1.2.0", to: "1.4.0"), "Update 1.2.0 → 1.4.0"),
        (.notManaged, "Not managed"),
        (.notLinked, "Not linked to agents"),
        (.findings(2), "2 findings"),
        (.cooldown(until: nil), "Cooldown"),
        (.cooldown(until: "4.3.0 eligible 2026-10-30T09:14:00Z"), "4.3.0 on 30 Oct"),
        (.notInstalled, "Not installed"),
        (.changedOnDisk, "Changed on disk"),
        (.needsSync(reason: "not in skills.lock"), "Needs sync"),
        (.needsSync(reason: "constraint changed from \"^1\" to \"^2\""), "Needs sync"),
        (.duplicate("skill \"x\" is provided by both a/b and c/d"), "Duplicate"),
        (.unknown("blocked by policy"), "Blocked by policy"),
        (.unknown("abandoned"), "Abandoned"),
        (.unknown("tag moved"), "Tag moved"),
        (.unknown("frozen"), "Frozen"),
        (.unknown(""), "Unknown"),
        (.unknown("  "), "Unknown"),
    ]

    @Test(arguments: healthLabels)
    func healthHasTheBoardWords(health: Health, expected: String) {
        #expect(Labels.health(health) == expected)
    }

    @Test func fixturesReadAsTheBoardRows() {
        #expect(Labels.health(DesignFixtures.pdf.health) == "Update 1.2.0 → 1.4.0")
        #expect(Labels.health(DesignFixtures.myNotes.health) == "2 findings")
        #expect(Labels.health(DesignFixtures.standupSummary.health) == "1 finding")
        #expect(Labels.health(DesignFixtures.testWriter.health) == "Blocked by policy")
        #expect(Labels.health(DesignFixtures.legacyLint.health) == "Abandoned")
        #expect(Labels.health(DesignFixtures.deployChecklist.health) == "Changed on disk")
        #expect(Labels.health(DesignFixtures.caveman.health) == "Not managed")
    }

    @Test func findingsPluralise() {
        #expect(Labels.findings(0) == "0 findings")
        #expect(Labels.findings(1) == "1 finding")
        #expect(Labels.findings(2) == "2 findings")
        #expect(Labels.health(.findings(1)) == "1 finding")
        #expect(Labels.health(.findings(12)) == "12 findings")
    }

    @Test func updateLabelIsBuiltFromTheTransition() {
        #expect(Labels.update == "Update")
        #expect(Labels.versionTransition(from: "1.2.0", to: "1.4.0") == "1.2.0 → 1.4.0")
        #expect(Labels.health(.updateAvailable(from: "2.1.0", to: "2.2.0")) == "Update 2.1.0 → 2.2.0")
    }

    /// The board's literal words, whatever the machine's locale or zone: day, abbreviated month, no year, GMT.
    @Test func cooldownNamesTheVersionAndTheDay() throws {
        #expect(Labels.cooldown(note: "4.3.0 eligible 2026-10-30T09:14:00Z") == "4.3.0 on 30 Oct")
        #expect(Labels.cooldown(note: "v4.3.0 eligible 2026-10-30T09:14:00Z") == "4.3.0 on 30 Oct")
        #expect(Labels.health(DesignFixtures.jiraCommunication.health) == "4.3.0 on 30 Oct")
        #expect(Labels.cooldown(note: "1.0.0 eligible 2026-12-31T23:30:00Z") == "1.0.0 on 31 Dec")
        #expect(Labels.cooldown(note: "1.0.0 eligible 2026-12-31T23:30:00-05:00") == "1.0.0 on 1 Jan")
        #expect(Formatters.dayMonth(try Date("2026-03-05T00:00:00Z", strategy: .iso8601)) == "5 Mar")
        #expect(Labels.cooldown(note: nil) == "Cooldown")
        #expect(Labels.cooldown(note: "waiting") == "Cooldown")
        #expect(Labels.cooldown(note: "4.3.0 eligible soon") == "Cooldown")
    }

    @Test func requiredByListsThePackages() {
        #expect(Labels.requiredBy(["caveman"]) == "Required by caveman")
        #expect(Labels.requiredBy(["caveman", "review-pr"]) == "Required by caveman, review-pr")
    }

    // MARK: - Severity

    @Test func severityWordsAndOrder() {
        #expect(Labels.severity(.neutral) == "Neutral")
        #expect(Labels.severity(.ok) == "OK")
        #expect(Labels.severity(.update) == "Update")
        #expect(Labels.severity(.warning) == "Warning")
        #expect(Labels.severity(.error) == "Error")
        #expect(Severity.allCases.sorted().last == .error)
        #expect(Severity.allCases.sorted() == [.neutral, .ok, .update, .warning, .error])
        #expect(Set(Severity.allCases.map(Labels.severity)).count == Severity.allCases.count)
    }

    // MARK: - Kind

    static let kindLabels: [(SkillEntry.Kind, String)] = [
        (.package("anthropics/skills"), "Package"),
        (.packageOnly("acme/gone"), "Package"),
        (.dependency("juliusbrussee/safe-refactor", via: ["caveman"]), "Dependency"),
        (.project, "Project skill"),
        (.handWritten, "Local skill"),
        (.notManaged(adopt: "github:juliusbrussee/caveman"), "Not managed"),
        (.notManaged(adopt: nil), "Not managed"),
    ]

    @Test(arguments: kindLabels)
    func kindHasThePillWords(kind: SkillEntry.Kind, expected: String) {
        #expect(Labels.kind(kind) == expected)
    }

    @Test func viewModeWords() {
        #expect(Labels.notSetUp == "Not set up")
        #expect(Labels.unknown == "Unknown")
    }
}
