import Foundation
import Testing

@testable import SkillcaskCore

@Suite struct InvocationTests {
    let project = Scope.project(URL(fileURLWithPath: "/tmp/p"))
    let caps = Fixture.capabilities
    let all = Capabilities(version: Version(0, 10, 0), features: Set(Capabilities.Feature.allCases))

    func argv(
        _ command: Invocation.Command, in scope: Scope? = nil, capabilities: Capabilities? = nil
    ) throws -> [String] {
        try Invocation(command, in: scope ?? project, capabilities: capabilities ?? caps).argv
    }

    @Test(arguments: [
        (Invocation.Command.version, ["--version"]),
        (.status, ["status", "--json"]),
        (.audit, ["audit", "--json"]),
        (.outdated, ["outdated", "--json"]),
        (.doctor(fix: false), ["doctor", "--json"]),
        (.doctor(fix: true), ["doctor", "--fix", "--json"]),
        (.info(.skill("notes")), ["info", "--json", "--", "notes"]),
        (.info(.package("acme/one")), ["info", "--json", "--", "acme/one"]),
        (.search(query: "jira", skillsSh: nil, remember: false), ["search", "--json", "--", "jira"]),
        (
            .search(query: "-x", skillsSh: .include, remember: true),
            ["search", "--json", "--skills-sh", "--remember", "--", "-x"]
        ),
        (.search(query: "q", skillsSh: .exclude, remember: false), ["search", "--json", "--no-skills-sh", "--", "q"]),
        (.diff(package: nil), ["diff"]),
        (.diff(package: "acme/one"), ["diff", "--", "acme/one"]),
        (.initialize, ["init"]),
        (.install(frozen: false), ["install"]),
        (.install(frozen: true), ["install", "--frozen"]),
        (.update(packages: []), ["update"]),
        (.update(packages: ["acme/one", "-g"]), ["update", "--", "acme/one", "-g"]),
        (
            .add(spec: "acme/one@^1", repository: nil, adopt: false, rename: [:], skills: []),
            ["add", "--", "acme/one@^1"]
        ),
        (
            .add(spec: "github:o/r", repository: "fix", adopt: true, rename: [:], skills: []),
            ["add", "--repository", "fix", "--adopt", "--", "github:o/r"]
        ),
        (.remove(packages: ["acme/one"]), ["remove", "--", "acme/one"]),
        (
            .authSet(host: "api.github.com", username: "oauth2"),
            ["auth", "set", "--username", "oauth2", "--", "api.github.com"]
        ),
        (.authSet(host: "gitlab.example", username: nil), ["auth", "set", "--", "gitlab.example"]),
        (.authRemove(host: "api.github.com"), ["auth", "remove", "--", "api.github.com"]),
    ])
    func projectArgv(command: Invocation.Command, expected: [String]) throws {
        #expect(try argv(command) == expected)
    }

    @Test func personalScopePutsGlobalFirst() throws {
        #expect(try argv(.status, in: .personal) == ["-g", "status", "--json"])
        #expect(
            try argv(.add(spec: "a/b", repository: nil, adopt: true, rename: [:], skills: []), in: .personal) == [
                "-g", "add", "--adopt", "--", "a/b",
            ])
        #expect(try argv(.authSet(host: "h", username: nil), in: .personal) == ["-g", "auth", "set", "--", "h"])
    }

    @Test func versionAndProjectsNeverTakeGlobal() throws {
        #expect(try argv(.version, in: .personal) == ["--version"])
        let roots = [URL(fileURLWithPath: "/Users/me/www"), URL(fileURLWithPath: "/tmp/-x")]
        #expect(
            try argv(.projects(roots: roots), in: .personal) == [
                "projects", "--json", "--", "/Users/me/www", "/tmp/-x",
            ])
    }

    @Test func mutationsGetJSONOnlyWithTheCapability() throws {
        #expect(try argv(.initialize, capabilities: all) == ["init", "--json"])
        #expect(try argv(.install(frozen: false), capabilities: all) == ["install", "--json"])
        #expect(try argv(.update(packages: ["a/b"]), capabilities: all) == ["update", "--json", "--", "a/b"])
        #expect(try argv(.remove(packages: ["a/b"]), capabilities: all) == ["remove", "--json", "--", "a/b"])
        let add = Invocation.Command.add(
            spec: "a/b", repository: nil, adopt: false, rename: ["x": "y", "a": "b"], skills: ["s1", "s2"])
        #expect(
            try argv(add, capabilities: all) == [
                "add", "--rename", "a=b", "--rename", "x=y", "--skill", "s1", "--skill", "s2", "--json", "--", "a/b",
            ])
        #expect(try !Invocation(.initialize, in: project, capabilities: caps).expectsDocument)
        #expect(try Invocation(.initialize, in: project, capabilities: all).expectsDocument)
    }

    @Test func renameAndSkillNeedTheirFeatures() throws {
        let rename = Invocation.Command.add(spec: "a/b", repository: nil, adopt: false, rename: ["x": "y"], skills: [])
        #expect(throws: CLIError.unsupported(feature: "add --rename")) {
            try Invocation(rename, in: project, capabilities: caps)
        }
        let skill = Invocation.Command.add(spec: "a/b", repository: nil, adopt: false, rename: [:], skills: ["s"])
        #expect(throws: CLIError.unsupported(feature: "add --skill")) {
            try Invocation(skill, in: project, capabilities: caps)
        }
    }

    @Test(arguments: [
        Invocation.Command.info(.skill("")),
        .search(query: "", skillsSh: nil, remember: false),
        .search(query: "q", skillsSh: nil, remember: true),
        .projects(roots: []),
        .diff(package: ""),
        .add(spec: "", repository: nil, adopt: false, rename: [:], skills: []),
        .add(spec: "a/b", repository: "", adopt: false, rename: [:], skills: []),
        .remove(packages: []),
        .remove(packages: [""]),
        .update(packages: [""]),
        .authSet(host: "", username: nil),
        .authSet(host: "h", username: ""),
        .authRemove(host: ""),
    ])
    func emptyDataIsRejected(command: Invocation.Command) {
        #expect(throws: CLIError.self) { try Invocation(command, in: project, capabilities: caps) }
    }

    @Test func classification() throws {
        let mutations: [Invocation.Command] = [
            .initialize, .install(frozen: false), .update(packages: []), .remove(packages: ["a"]), .doctor(fix: true),
        ]
        for command in mutations {
            #expect(try Invocation(command, in: project, capabilities: caps).isMutation, "\(command)")
        }
        for command in [
            Invocation.Command.status, .doctor(fix: false), .outdated,
            .search(query: "q", skillsSh: nil, remember: false), .version,
        ] {
            #expect(try !Invocation(command, in: project, capabilities: caps).isMutation, "\(command)")
        }
        #expect(try Invocation(.info(.package("a/b")), in: project, capabilities: caps).needsNetwork)
        #expect(try !Invocation(.info(.skill("b")), in: project, capabilities: caps).needsNetwork)
        #expect(try !Invocation(.status, in: project, capabilities: caps).needsNetwork)
        #expect(try Invocation(.outdated, in: project, capabilities: caps).needsNetwork)
    }

    @Test func displayCommandQuotesOnlyWhatNeedsIt() throws {
        let plain = try Invocation(
            .add(spec: "acme/one@^1.0", repository: nil, adopt: false, rename: [:], skills: []), in: .personal,
            capabilities: caps)
        #expect(plain.displayCommand == "skillcask -g add -- acme/one@^1.0")
        let spaced = try Invocation(
            .search(query: "two words'", skillsSh: nil, remember: false), in: project, capabilities: caps)
        #expect(spaced.displayCommand == #"skillcask search --json -- 'two words'\'''"#)
    }

    @Test func stdinIsNullUnlessGiven() throws {
        #expect(try Invocation(.status, in: project, capabilities: caps).stdin == .null)
        let auth = try Invocation(
            .authSet(host: "h", username: nil), in: project, capabilities: caps, stdin: .text("tok"))
        #expect(auth.stdin == .text("tok") && !auth.displayCommand.contains("tok"))
    }
}

@Suite struct ScopeTests {
    @Test func projectAtResolvesTildeAndDots() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(Scope.project(at: "~/www/../www/a").root.path == "\(home)/www/a")
        #expect(Scope.personal.root.path == home)
        #expect(Scope.personal.isPersonal && !Scope.project(at: "/tmp").isPersonal)
    }
}
