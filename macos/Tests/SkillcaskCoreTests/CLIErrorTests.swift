import Foundation
import Testing

@testable import SkillcaskCore

@Suite struct ExitCodeTests {
    @Test(arguments: [
        (Int32(1), ExitCode.problem), (2, .signIn), (3, .network), (4, .integrity), (5, .file), (101, .other(101)),
        (0, .other(0)),
    ])
    func maps(status: Int32, expected: ExitCode) {
        #expect(ExitCode(status) == expected)
        #expect(ExitCode(status).status == status)
    }
}

@Suite struct StderrReportTests {
    @Test(arguments: Fixture.versions) func errorAndHintOutsideAProject(version: String) throws {
        let report = StderrReport(parsing: try Fixture.text(version, "status.noproject.stderr"))
        #expect(report.error == "skills.toml not found")
        #expect(report.hint == "run skillcask init")
        #expect(report.warnings.isEmpty && report.notes.isEmpty && report.other.isEmpty)
    }

    @Test func warningsNotesAndProgressLines() {
        let stderr = """
            warning: netresearch/agent-jira-skill is abandoned; use netresearch/jira-skill instead
            note: 2 packages checked
            fetching https://repo.packagist.org/p2/acme/one.json
            error: 1 finding(s)
            error: second error stays visible

            """
        let report = StderrReport(parsing: stderr)
        #expect(report.warnings == ["netresearch/agent-jira-skill is abandoned; use netresearch/jira-skill instead"])
        #expect(report.notes == ["2 packages checked"])
        #expect(report.error == "1 finding(s)" && report.hint == nil)
        #expect(
            report.other == [
                "fetching https://repo.packagist.org/p2/acme/one.json", "error: second error stays visible",
            ])
    }

    @Test func emptyAndColouredInput() {
        #expect(StderrReport(parsing: "") == StderrReport())
        let coloured = "\u{1B}[31merror\u{1B}[0m: boom\n  \u{1B}[36mhint\u{1B}[0m: try again\n"
        let report = StderrReport(parsing: coloured)
        #expect(report.error == "boom" && report.hint == "try again")
    }
}

@Suite struct VersionTests {
    @Test(arguments: [
        ("0.9.1", Version(0, 9, 1)),
        ("v0.9.1", Version(0, 9, 1)),
        ("0.10.0-rc1", Version(0, 10, 0, prerelease: "rc1")),
        ("12.0.3", Version(12, 0, 3)),
    ])
    func parses(text: String, expected: Version) {
        #expect(Version(text) == expected)
        #expect(Version(expected.description) == expected)
    }

    @Test(arguments: ["", "0.9", "0.9.1.2", "a.b.c", "0.9.-1", "0.9.1-", "0.9.1 (sha)"])
    func rejects(text: String) {
        #expect(Version(text) == nil)
    }

    @Test func cliOutput() {
        #expect(Version(cliOutput: "skillcask 0.9.1 (1afcd7c81d2e)\n") == Version(0, 9, 1))
        #expect(Version(cliOutput: "skillcask 0.10.0-rc1 (unknown)") == Version(0, 10, 0, prerelease: "rc1"))
        #expect(Version(cliOutput: "error: unexpected argument") == nil)
        #expect(Version(cliOutput: "skillcask") == nil)
        #expect(Version(cliOutput: "cargo 1.80.0") == nil)
    }

    @Test func ordersNumericallyWithPrereleaseFirst() {
        let ordered = [
            Version(0, 9, 1), Version(0, 10, 0, prerelease: "rc1"), Version(0, 10, 0), Version(0, 10, 1),
            Version(1, 0, 0),
        ]
        #expect(ordered == ordered.shuffled().sorted())
        #expect(Version(0, 10, 0, prerelease: "rc1") < Version(0, 10, 0))
        #expect(Version(0, 10, 0, prerelease: "beta") < Version(0, 10, 0, prerelease: "rc1"))
        #expect(!(Version(0, 9, 1) < Version(0, 9, 1)))
    }
}

@Suite struct CapabilitiesTests {
    @Test func minimumVersionHasNoPlannedFeature() {
        let caps = Capabilities(version: Capabilities.minimum)
        #expect(caps.features.isEmpty && !caps.isTooOld)
        for feature in Capabilities.Feature.allCases {
            #expect(!caps.supports(feature))
        }
    }

    @Test func olderIsTooOldAndNewerIsNot() {
        #expect(Capabilities(version: Version(0, 9, 3)).isTooOld)
        #expect(Capabilities(version: Version(0, 9, 4, prerelease: "rc1")).isTooOld)
        #expect(!Capabilities(version: Version(0, 9, 4)).isTooOld)
        #expect(!Capabilities(version: Version(0, 10, 0)).isTooOld)
    }

    /// Every feature is planned: no release turns one on until `shipped` names it.
    @Test func aNewerReleaseHasNoPlannedFeature() {
        #expect(Capabilities(version: Version(1, 0, 0)).features.isEmpty)
    }

    @Test func explicitFeatureSet() {
        let caps = Capabilities(version: Version(0, 10, 0), features: [.jsonMutations])
        #expect(caps.supports(.jsonMutations) && !caps.supports(.diffJSON))
    }
}
