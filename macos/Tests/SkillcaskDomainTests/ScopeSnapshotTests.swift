import Foundation
import SkillcaskCore
import Testing

@testable import SkillcaskDomain

enum Sample {
    static let status = #"""
        {"entries":[{"adopt":null,"ok":true,"package":"netresearch/agent-jira-skill","skill":"jira-communication","state":"ok","version":"v4.3.0"},{"adopt":null,"ok":false,"package":"netresearch/agent-jira-skill","skill":"jira-syntax","state":"modified","version":"v4.3.0"},{"adopt":null,"ok":true,"package":null,"skill":"notes","state":"project","version":null},{"adopt":"github:x/y/z","ok":true,"package":null,"skill":"z","state":"not managed","version":null},{"adopt":null,"ok":true,"package":"acme/dep (via netresearch/agent-jira-skill)","skill":"d","state":"ok","version":"1.0.0"},{"adopt":null,"ok":false,"package":"acme/gone","skill":null,"state":"not in skills.lock","version":null},{"adopt":null,"ok":true,"package":null,"skill":"mine","state":"hand-written","version":null}],"ok":false,"policy":{"allow-ranges":{"from":"skills.toml","value":true},"min-release-age":{"from":"config.toml","value":"72h"}},"repositories":[{"allowed":true,"name":"packagist","type":"composer","url":"https://repo.packagist.org/"}],"targets":{"dirs":[".claude/skills"],"entries":["claude"],"from":"default"}}
        """#
    static let audit = #"""
        {"ok":false,"skills":[{"commands":[],"env":[],"findings":[{"line":null,"message":"not installed","path":".agents/skills/jira-syntax","rule":"modified"}],"kind":"package","network":[],"package":"netresearch/agent-jira-skill","path":".agents/skills/jira-syntax","paths":[],"scripts":[],"skill":"jira-syntax","version":"v4.3.0"},{"commands":["curl"],"env":["HOME"],"findings":[{"line":5,"message":"downloads code into a shell","path":".skills/notes/SKILL.md","rule":"risky-pattern"}],"kind":"project","network":["x.example"],"package":null,"path":".skills/notes","paths":["~/.ssh"],"scripts":[],"skill":"notes","version":null}]}
        """#
    static let outdated = #"""
        {"behind":["netresearch/agent-jira-skill"],"packages":[{"latest":"v5.0.0","locked":"v4.3.0","note":null,"package":"netresearch/agent-jira-skill","within":"v4.4.0"},{"latest":"1.0.0","locked":"1.0.0","note":null,"package":"acme/dep","within":"1.0.0"}]}
        """#
    static let doctor =
        #"{"fixed":[],"ok":false,"passed":["links: 5 ok"],"problems":[".claude/skills/jira-syntax: link wrong"],"warnings":[]}"#

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    static func snapshot(outdated: Bool = true, audit: Bool = true) throws -> ScopeSnapshot {
        try ScopeSnapshot(
            status: decode(StatusDocument.self, status), audit: audit ? decode(AuditDocument.self, Self.audit) : nil,
            doctor: decode(DoctorDocument.self, doctor),
            outdated: outdated ? decode(OutdatedDocument.self, Self.outdated) : nil)
    }
}

@Suite struct ScopeSnapshotTests {
    @Test func entriesJoinStatusAuditAndOutdated() throws {
        let snapshot = try Sample.snapshot()
        #expect(
            snapshot.entries.map(\.id) == ["jira-communication", "jira-syntax", "notes", "z", "d", "acme/gone", "mine"])
        let byId = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.id, $0) })
        #expect(byId["jira-communication"]?.health == .updateAvailable(from: "v4.3.0", to: "v4.4.0"))
        #expect(byId["jira-communication"]?.kind == .package("netresearch/agent-jira-skill"))
        #expect(
            byId["jira-syntax"]?.health == .changedOnDisk && byId["jira-syntax"]?.path == ".agents/skills/jira-syntax")
        #expect(
            byId["notes"]?.health == .findings(1) && byId["notes"]?.kind == .project
                && byId["notes"]?.findings.first?.line == 5)
        #expect(byId["z"]?.kind == .notManaged(adopt: "github:x/y/z") && byId["z"]?.health == .notManaged)
        #expect(
            byId["d"]?.kind == .dependency("acme/dep", via: ["netresearch/agent-jira-skill"])
                && byId["d"]?.health == .installed)
        #expect(
            byId["acme/gone"]?.kind == .packageOnly("acme/gone")
                && byId["acme/gone"]?.health == .needsSync(reason: "not in skills.lock"))
        #expect(byId["mine"]?.kind == .handWritten && byId["mine"]?.health == .localSkill)
    }

    @Test func reachIsCarriedFromTheAuditRow() throws {
        let byId = try Dictionary(uniqueKeysWithValues: Sample.snapshot().entries.map { ($0.id, $0) })
        #expect(
            byId["notes"]?.reach
                == Reach(commands: ["curl"], network: ["x.example"], paths: ["~/.ssh"], env: ["HOME"], scripts: []))
        #expect(byId["jira-syntax"]?.reach?.isEmpty == true)
        // No audit row: not audited, which is not the same as an empty reach.
        #expect(byId["z"]?.reach == nil && byId["mine"]?.reach == nil)
        #expect(try Sample.snapshot(audit: false).entries.allSatisfy { $0.reach == nil })
    }

    @Test func attentionCountsWorstPerRowPlusUpdates() throws {
        let attention = try Sample.snapshot().attention
        #expect(attention == Attention(errors: 2, warnings: 2, updates: 2))
        #expect(attention.needing == 4 && attention.worst == .error)
        #expect(Attention(errors: 0, warnings: 0, updates: 1).worst == .update)
        #expect(Attention().worst == nil)
    }

    @Test func scopeLevelRows() throws {
        let snapshot = try Sample.snapshot()
        #expect(
            snapshot.policy == [
                ScopeSnapshot.PolicyRow(key: "min-release-age", value: "72h", from: "config.toml"),
                ScopeSnapshot.PolicyRow(key: "allow-ranges", value: "true", from: "skills.toml"),
            ])
        #expect(snapshot.targets?.entries == ["claude"] && snapshot.repositories.count == 1)
        #expect(snapshot.doctor?.ok == false && snapshot.doctor?.problems.count == 1)
        #expect(snapshot.updatesChecked && snapshot.availableUpdates.map(\.package) == ["netresearch/agent-jira-skill"])
        #expect(
            snapshot.entry(id: "notes")?.name == "notes" && snapshot.entry(id: "nope") == nil
                && snapshot.entry(id: nil) == nil)
    }

    @Test func requirerSkillsNameTheSkillsOfTheViaPackages() throws {
        let snapshot = try Sample.snapshot()
        let byId = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.id, $0) })
        let dependency = try #require(byId["d"])
        #expect(snapshot.requirerSkills(of: dependency) == ["jira-communication", "jira-syntax"])
        let package = try #require(byId["jira-syntax"])
        #expect(snapshot.requirerSkills(of: package) == [])
        let project = try #require(byId["notes"])
        #expect(snapshot.requirerSkills(of: project) == [])
    }

    @Test func withoutOutdatedAndAuditNothingIsGuessed() throws {
        let snapshot = try Sample.snapshot(outdated: false, audit: false)
        #expect(!snapshot.updatesChecked && snapshot.availableUpdates.isEmpty)
        #expect(snapshot.entry(id: "jira-communication")?.health == .installed)
        #expect(snapshot.entry(id: "notes")?.health == .projectSkill && snapshot.entry(id: "notes")?.path == nil)
        #expect(snapshot.attention == Attention(errors: 2, warnings: 1, updates: 0))
    }
}

@Suite struct FilterTests {
    let entries: [SkillEntry]

    init() throws {
        entries = try Sample.snapshot().entries
    }

    @Test func chips() {
        #expect(Filter.all.apply(entries).count == 7)
        #expect(Set(Filter.needsAttention.apply(entries).map(\.id)) == ["jira-syntax", "notes", "z", "acme/gone"])
        #expect(Filter.updates.apply(entries).map(\.id) == ["jira-syntax", "jira-communication"])
        #expect(Filter.notManaged.apply(entries).map(\.id) == ["z"])
        #expect(Set(Filter.projectSkills.apply(entries).map(\.id)) == ["notes", "mine"])
    }

    @Test func sortedWorstFirstThenByName() {
        let ids = Filter.all.apply(entries).map(\.id)
        #expect(ids == ["acme/gone", "jira-syntax", "notes", "z", "jira-communication", "d", "mine"])
    }

    @Test func queryMatchesNamePackageAndDescription() {
        #expect(Filter.all.apply(entries, query: "JIRA").map(\.id).sorted() == ["jira-communication", "jira-syntax"])
        #expect(Filter.all.apply(entries, query: "acme").map(\.id).sorted() == ["acme/gone", "d"])
        #expect(Filter.needsAttention.apply(entries, query: "notes").map(\.id) == ["notes"])
        #expect(Filter.all.apply(entries, query: "zzz").isEmpty)
    }
}

@Suite struct PresentationTests {
    @Test func failedLoadMapping() {
        #expect(Presentation.forFailedLoad(.binaryMissing(searched: ["/x"])) == .cliMissing(searched: ["/x"]))
        #expect(
            Presentation.forFailedLoad(.tooOld(found: Version(0, 8, 0), needs: Version(0, 9, 1)))
                == .cliTooOld(found: Version(0, 8, 0), needs: Version(0, 9, 1)))
        let missing = CLIError.failed(
            code: .problem, message: "skills.toml not found", hint: "run skillcask init", stderr: "")
        #expect(Presentation.forFailedLoad(missing) == .noManifest)
        let other = CLIError.failed(code: .file, message: "skills.lock: permission denied", hint: nil, stderr: "")
        #expect(Presentation.forFailedLoad(other) == .error(other))
        #expect(Presentation.forFailedLoad(.cancelled) == .error(.cancelled))
    }
}

/// What `install --frozen` restores, from the `modified` findings `audit` reports on locked skills.
@Suite struct LockRestoreTests {
    static func finding(_ rule: String, _ message: String) throws -> AuditDocument.Finding {
        try Sample.decode(
            AuditDocument.Finding.self,
            #"{"rule":"\#(rule)","path":".agents/skills/x","line":null,"message":"\#(message)"}"#)
    }

    static func entry(_ name: String, _ kind: SkillEntry.Kind, _ findings: [AuditDocument.Finding]) -> SkillEntry {
        SkillEntry(
            id: name, name: name, kind: kind, source: nil, version: nil, state: .ok, health: .installed, update: nil,
            findings: findings, path: nil, description: nil, reach: nil)
    }

    let edited: AuditDocument.Finding
    let missing: AuditDocument.Finding

    init() throws {
        edited = try Self.finding(
            "modified", "modified after skillcask installed it; run `skillcask install` to restore")
        missing = try Self.finding("modified", "not installed")
    }

    @Test func modifiedMapsToChangedOrNotInstalledAndKeepsTheMessage() throws {
        #expect(edited.lockRestoreReason == .changed)
        #expect(missing.lockRestoreReason == .notInstalled)
        #expect(try Self.finding("risky-pattern", "not installed").lockRestoreReason == nil)
        let restore = Self.entry("a", .package("v/a"), [missing]).lockRestore
        #expect(restore == LockRestore(skill: "a", reason: .notInstalled, message: "not installed"))
        #expect(Self.entry("b", .package("v/b"), [edited]).lockRestore?.message == edited.message)
    }

    @Test func onlyLockedSkillsRestoreInListOrderOncePerName() {
        let entries = [
            Self.entry("a", .package("v/a"), [edited]),
            Self.entry("ok", .package("v/ok"), []),
            Self.entry("mine", .handWritten, [edited]),
            Self.entry("notes", .project, [edited]),
            Self.entry("z", .notManaged(adopt: nil), [missing]),
            Self.entry("d", .dependency("v/d", via: ["v/a"]), [missing]),
            Self.entry("a", .package("v/a2"), [edited]),
        ]
        #expect(LockRestore.restores(in: entries).map(\.skill) == ["a", "d"])
        #expect(LockRestore.restores(in: entries).map(\.reason) == [.changed, .notInstalled])
    }

    @Test func snapshotRestoresComeFromItsAudit() throws {
        #expect(
            try Sample.snapshot().lockRestores
                == [LockRestore(skill: "jira-syntax", reason: .notInstalled, message: "not installed")])
        #expect(try Sample.snapshot(audit: false).lockRestores.isEmpty)
    }
}
