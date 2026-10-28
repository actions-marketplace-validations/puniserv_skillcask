import Foundation
import SkillcaskCore
import Testing

@testable import SkillcaskDomain

func finding(_ rule: String) throws -> AuditDocument.Finding {
    try JSONDecoder()
        .decode(
            AuditDocument.Finding.self,
            from: Data(#"{"rule":"\#(rule)","path":".skills/x/SKILL.md","line":1,"message":"m"}"#.utf8))
}

func update(
    locked: String?, within: String?, latest: String?, note: String? = nil, eligible: String? = nil
) throws -> Update {
    let json: [String: Any?] = [
        "package": "a/b", "locked": locked, "within": within, "latest": latest, "note": note, "eligible": eligible,
    ]
    let data = try JSONSerialization.data(withJSONObject: json.mapValues { $0 ?? NSNull() })
    return Update(try JSONDecoder().decode(OutdatedDocument.Package.self, from: data))
}

@Suite struct SkillStateTests {
    @Test(arguments: [
        ("ok", SkillState.ok), ("project", .project), ("hand-written", .handWritten), ("not managed", .notManaged),
        ("not linked", .notLinked), ("not installed", .notInstalled), ("modified", .modified),
        ("not in skills.lock", .notInLock), ("not in skills.toml", .notInManifest),
        ("constraint changed from \"^1\" to \"^2\"", .drift("constraint changed from \"^1\" to \"^2\"")),
        ("repository changed", .drift("repository changed")),
        ("changed from ref to version", .drift("changed from ref to version")),
        ("skill selection changed", .drift("skill selection changed")), ("rename changed", .drift("rename changed")),
        ("skill \"x\" is provided by both a/b and c/d", .duplicate("skill \"x\" is provided by both a/b and c/d")),
        ("something new", .other("something new")),
    ])
    func parses(text: String, expected: SkillState) {
        #expect(SkillState(cliState: text) == expected)
    }

    @Test func healthyMirrorsTheCLI() {
        let healthy = [SkillState.ok, .project, .handWritten, .notManaged].map { $0.isHealthy }
        let unhealthy = [SkillState.notLinked, .notInstalled, .modified, .notInLock, .drift("x"), .other("y")]
            .map { $0.isHealthy }
        #expect(healthy == [true, true, true, true])
        #expect(unhealthy == [false, false, false, false, false, false])
    }
}

@Suite struct HealthMappingTests {
    @Test(arguments: [
        (SkillState.ok, Health.installed), (.project, .projectSkill), (.handWritten, .localSkill),
        (.notManaged, .notManaged),
        (.notLinked, .notLinked), (.notInstalled, .notInstalled), (.modified, .changedOnDisk),
        (.notInLock, .needsSync(reason: "not in skills.lock")),
        (.notInManifest, .needsSync(reason: "not in skills.toml")),
        (.drift("repository changed"), .needsSync(reason: "repository changed")),
        (.duplicate("dup"), .duplicate("dup")), (.other("new"), .unknown("new")),
    ])
    func stateAlone(state: SkillState, expected: Health) {
        #expect(HealthMapping.health(state: state, update: nil, findings: []) == expected)
    }

    @Test func findingsOutrankUpdatesButNotErrors() throws {
        let risky = try [finding("risky-pattern")]
        let invisible = try finding("invisible-character")
        let modified = try finding("modified")
        let newer = try update(locked: "1.0.0", within: "1.1.0", latest: "1.1.0")
        #expect(HealthMapping.health(state: .ok, update: newer, findings: risky) == .findings(1))
        #expect(HealthMapping.health(state: .project, update: nil, findings: risky + [invisible]) == .findings(2))
        #expect(HealthMapping.health(state: .ok, update: newer, findings: [modified]) == .changedOnDisk)
        #expect(HealthMapping.health(state: .notInstalled, update: newer, findings: risky) == .notInstalled)
        #expect(HealthMapping.health(state: .notManaged, update: nil, findings: risky) == .findings(1))
    }

    @Test func updatesAndCooldowns() throws {
        let newer = try update(locked: "1.0.0", within: "1.1.0", latest: "2.0.0")
        #expect(
            HealthMapping.health(state: .ok, update: newer, findings: [])
                == .updateAvailable(from: "1.0.0", to: "1.1.0"))
        let current = try update(locked: "1.0.0", within: "1.0.0", latest: "2.0.0")
        #expect(HealthMapping.health(state: .ok, update: current, findings: []) == .installed)
        #expect(current.outsideRange == "2.0.0" && current.available == nil)
        // As `outdated` prints it: `within` is the waiting version, named in the note.
        let cooling = try update(
            locked: "1.0.0", within: "1.1.0", latest: "1.1.0", note: "1.1.0 eligible 2026-10-26T21:44:27Z")
        #expect(HealthMapping.health(state: .ok, update: cooling, findings: []) == .cooldown(until: cooling.note))
        #expect(cooling.eligible == ISO8601DateFormatter().date(from: "2026-10-26T21:44:27Z"))
        let planned = try update(locked: "1.0.0", within: "1.1.0", latest: "1.1.0", eligible: "2026-10-27T00:00:00Z")
        #expect(planned.eligible == ISO8601DateFormatter().date(from: "2026-10-27T00:00:00Z"))
        let unlocked = try update(locked: nil, within: "1.0.0", latest: "1.0.0")
        #expect(
            unlocked.available == nil
                && HealthMapping.health(state: .notInLock, update: unlocked, findings: [])
                    == .needsSync(reason: "not in skills.lock")
        )
    }

    @Test func severityOrder() {
        #expect(
            Severity.neutral < Severity.ok && Severity.ok < Severity.update && Severity.update < Severity.warning
                && Severity.warning < Severity.error)
        #expect(Health.installed.severity == .ok && Health.updateAvailable(from: "a", to: "b").severity == .update)
        #expect(Health.findings(1).severity == .warning && Health.notManaged.severity == .warning)
        #expect(Health.notInstalled.severity == .error && Health.needsSync(reason: "").severity == .error)
    }
}
