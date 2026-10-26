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
