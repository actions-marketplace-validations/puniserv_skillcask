import Foundation
import Testing

@testable import SkillcaskCore

// Samples printed by skillcask 0.7.0 for a project with netresearch/agent-jira-skill and a
// project skill, some trimmed, plus a key no version prints yet: D32 only ever adds keys.

private func decode<T: Decodable>(_ type: T.Type, _ json: String, status: Int32 = 0) -> T? {
    RunResult(command: "", status: status, stdout: Data(json.utf8), stderr: "").decode(type)
}

@Test func statusWithAProblemStillDecodes() throws {
    let json = #"""
        {"entries":[{"ok":true,"package":"netresearch/agent-jira-skill","skill":"jira-communication","state":"ok","version":"v4.2.0"},{"ok":false,"package":"netresearch/agent-jira-skill","skill":"jira-syntax","state":"not installed","version":"v4.2.0"},{"ok":true,"package":null,"skill":"notes","state":"project","version":null}],"ok":false,"policy":{"allow-ranges":{"from":"skills.toml","value":true},"min-release-age":{"from":"skills.toml","value":"72h"}},"targets":{"dirs":[".claude/skills"],"entries":["claude"],"from":"default"},"added-later":1}
        """#
    let doc = try #require(decode(StatusDoc.self, json, status: 1))
    #expect(!doc.ok)
    #expect(doc.entries.map(\.state) == ["ok", "not installed", "project"])
    #expect(doc.entries[2].package == nil && doc.entries[2].version == nil)
    #expect(doc.targets?.dirs == [".claude/skills"])
}

@Test func outdated() throws {
    let json = #"""
        {"behind":[],"packages":[{"latest":"v4.3.0","locked":"v4.2.0","note":"v4.3.0 eligible 2026-10-26T21:44:27Z","package":"netresearch/agent-jira-skill","within":"v4.3.0"},{"latest":null,"locked":null,"note":null,"package":"acme/new","within":null}]}
        """#
    let doc = try #require(decode(OutdatedDoc.self, json))
    #expect(doc.packages[0].within == "v4.3.0")
    #expect(doc.packages[1].locked == nil)
}

@Test func infoOfAPackage() throws {
    let json = #"""
        {"abandoned":"netresearch/jira-skill","description":"Netresearch AI skill for Jira API operations and wiki markup syntax","license":["(MIT AND CC-BY-SA-4.0)"],"locked":true,"package":"netresearch/agent-jira-skill","repository":"https://repo.packagist.org/","requires":{},"skills":[{"description":"Use when writing or formatting Jira descriptions.","name":"jira-syntax"},{"description":null,"name":"bare"}],"source":"composer","version":"v4.2.0","versions":["v4.3.0","v4.2.0"],"why":["netresearch/agent-jira-skill: in skills.toml as \"^4.2\""]}
        """#
    let doc = try #require(decode(InfoDoc.self, json))
    #expect(doc.package == "netresearch/agent-jira-skill")
    #expect(doc.abandoned?.replacement == "netresearch/jira-skill")
    #expect(doc.skills?.map(\.name) == ["jira-syntax", "bare"])
    #expect(doc.requires == [:])
    #expect(doc.kind == nil)
}

@Test func infoAbandonedWithoutReplacementOrNot() throws {
    let yes = try #require(decode(InfoDoc.self, #"{"package":"a/b","abandoned":true}"#))
    #expect(yes.abandoned != nil && yes.abandoned?.replacement == nil)
    let no = try #require(decode(InfoDoc.self, #"{"package":"a/b","abandoned":null}"#))
    #expect(no.abandoned == nil)
}

@Test func infoOfASkillName() throws {
    let pkg = try #require(decode(InfoDoc.self, #"""
        {"from":null,"kind":"package","package":"netresearch/agent-jira-skill","skill":"jira-syntax","version":"v4.2.0","why":["netresearch/agent-jira-skill: in skills.toml as \"^4.2\""]}
        """#))
    #expect(pkg.kind == "package" && pkg.skill == "jira-syntax")
    let local = try #require(decode(InfoDoc.self, #"{"kind":"project","path":".skills/notes","skill":"notes"}"#))
    #expect(local.path == ".skills/notes" && local.package == nil)
}

@Test func search() throws {
    let doc = try #require(decode(SearchDoc.self, #"""
        {"results":[{"description":"Netresearch AI skill for Jira API operations and wiki markup syntax","name":"netresearch/jira-skill"},{"description":null,"name":"acme/x"}]}
        """#))
    #expect(doc.results.map(\.name) == ["netresearch/jira-skill", "acme/x"])
    #expect(!doc.asksSkillsSh)
}

@Test func searchSkillsSh() throws {
    let doc = try #require(decode(SearchDoc.self, #"""
        {"results":[{"description":null,"installs":594431,"name":"github:juliusbrussee/caveman/caveman","source":"skills.sh"}],"skills-sh":null}
        """#))
    #expect(doc.asksSkillsSh && doc.results[0].installs == 594431 && doc.results[0].source == "skills.sh")
    #expect(try #require(decode(SearchDoc.self, #"{"results":[],"skills-sh":false}"#)).asksSkillsSh == false)
}

@Test func statusRepositories() throws {
    let doc = try #require(decode(StatusDoc.self, #"""
        {"entries":[],"ok":true,"repositories":[{"allowed":true,"name":"packagist","type":"composer","url":"https://repo.packagist.org/"},{"allowed":false,"name":"github","type":"github","url":"https://api.github.com/"}]}
        """#))
    #expect(doc.repositories?.map(\.allowed) == [true, false])
}

@Test func doctor() throws {
    let doc = try #require(decode(DoctorDoc.self, #"""
        {"fixed":[],"ok":false,"passed":["targets: no links left in former target directories","git index: no managed paths committed",".gitignore: managed block up to date"],"problems":[".claude/skills/jira-syntax: link wrong",".agents/skills/jira-syntax: not installed (netresearch/agent-jira-skill); run `skillcask install`"],"warnings":[]}
        """#, status: 1))
    #expect(!doc.ok && doc.problems.count == 2 && doc.passed.count == 3)
}

@Test func noDocumentOnAnError() {
    #expect(decode(InfoDoc.self, "", status: 1) == nil)
}

@Test func runReportsExitCodeAndStderr() async {
    let r = await CLI.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo out; echo err >&2; exit 3"], in: URL(fileURLWithPath: "/"))
    #expect(r.status == 3)
    #expect(String(decoding: r.stdout, as: UTF8.self) == "out\n")
    #expect(r.stderr == "err\n")
}

@Test func notManagedEntryCarriesTheAdoptSource() throws {
    let doc = try #require(decode(StatusDoc.self, #"""
        {"entries":[{"adopt":"github:JuliusBrussee/caveman/cavecrew","ok":true,"package":null,"skill":"cavecrew","state":"not managed","version":null},{"adopt":null,"ok":true,"package":null,"skill":"mine","state":"not managed","version":null}],"ok":true}
        """#))
    #expect(doc.entries.map(\.adopt) == ["github:JuliusBrussee/caveman/cavecrew", nil])
    // 0.7.0 prints no `adopt` key.
    #expect(try #require(decode(StatusDoc.self, #"{"entries":[{"ok":true,"package":null,"skill":"a","state":"ok","version":null}],"ok":true}"#)).entries[0].adopt == nil)
}

@Test func versionGate() {
    #expect(CLI.version("skillcask 0.7.0 (4235d7f73ebd)\n") == [0, 7, 0])
    #expect(CLI.tooOld("skillcask 0.8.0 (4235d7f73ebd)") == nil)
    #expect(CLI.tooOld("skillcask 0.7.0 (4235d7f73ebd)") != nil)
    #expect(CLI.tooOld("skillcask 0.10.1") == nil)
    #expect(CLI.tooOld("skillcask 0.5.0 (abc)")?.contains("0.5.0 is too old") == true)
    #expect(CLI.tooOld("error: unexpected argument") != nil)
}

@Test func projects() throws {
    let doc = try #require(decode(ProjectsDoc.self, #"{"projects":[{"path":"/Users/me/www/a"},{"path":"/Users/me/www/b/c"}]}"#))
    #expect(doc.projects.map(\.path) == ["/Users/me/www/a", "/Users/me/www/b/c"])
}

@Test func auditWithFindingsStillDecodes() throws {
    let json = #"""
        {"ok":false,"skills":[{"commands":[],"env":[],"findings":[],"kind":"package","network":[],"package":"juliusbrussee/caveman","path":".agents/skills/safe-refactor","paths":[],"scripts":[],"skill":"safe-refactor","version":"v4.0.1"},{"commands":["git"],"env":["HOME"],"findings":[{"line":5,"message":"downloads code into a shell","path":".skills/notes/SKILL.md","rule":"risky-pattern"},{"line":null,"message":"not installed","path":".agents/skills/x","rule":"modified"}],"kind":"project","network":["x.example"],"package":null,"path":".skills/notes","paths":["~/.ssh"],"scripts":["run.sh"],"skill":"notes","version":null}]}
        """#
    let doc = try #require(decode(AuditDoc.self, json, status: 1))
    #expect(!doc.ok)
    let notes = doc.skills[1]
    #expect(notes.path == ".skills/notes" && notes.network == ["x.example"] && notes.paths == ["~/.ssh"])
    #expect(notes.findings.map(\.line) == [5, nil])
    #expect(notes.findings[0].rule == "risky-pattern")
}

@Test func config() throws {
    // `-g config --json` of a master build with SKILLCASK_ALLOW_SOURCES set; `later` is a key no version prints yet.
    let json = #"""
        {"file":"/Users/me/.config/skillcask/config.toml","settings":{"agents.targets":{"from":"config.toml","value":["claude","codex"]},"policy.allow-ranges":{"from":"config.toml, enforced","value":false},"policy.allow-sources":{"from":"environment","value":["github","packagist"]},"policy.enforce":{"from":null,"value":null},"policy.min-release-age":{"from":"default","value":"72h"},"search.skills-sh":{"from":"config.toml","value":true},"later":{"from":"default","value":3}}}
        """#
    let doc = try #require(decode(ConfigDoc.self, json))
    #expect(doc.file == "/Users/me/.config/skillcask/config.toml")
    #expect(doc.settings["agents.targets"]?.value == .list(["claude", "codex"]))
    #expect(doc.settings["policy.allow-ranges"]?.value == .bool(false))
    #expect(doc.settings["policy.allow-ranges"]?.from == "config.toml, enforced")
    #expect(doc.settings["policy.allow-sources"]?.from == "environment")
    #expect(doc.settings["policy.enforce"]?.value == ConfigDoc.Value.none)
    #expect(doc.settings["policy.enforce"]?.from == nil)
    #expect(doc.settings["policy.min-release-age"]?.value == .string("72h"))
    #expect(doc.settings["search.skills-sh"]?.value == .bool(true))
    #expect(doc.settings["later"]?.value == .string("3.0"))
}

@Test func configVersionGate() {
    #expect(CLI.atLeast(CLI.configMinimum, "skillcask 0.9.4 (abc)"))
    #expect(CLI.atLeast(CLI.configMinimum, "skillcask 0.10.0"))
    #expect(!CLI.atLeast(CLI.configMinimum, "skillcask 0.9.3 (abc)"))
    #expect(!CLI.atLeast(CLI.configMinimum, "error"))
}
