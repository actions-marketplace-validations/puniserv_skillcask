import Foundation
import Testing

@testable import SkillcaskCore

@Suite struct EnvironmentPolicyTests {
    @Test func setsStripsAndExtendsPath() {
        let base = [
            "PATH": "/usr/bin:/opt/homebrew/bin", "CLICOLOR_FORCE": "1", "CLAUDECODE": "1", "HOME": "/Users/me",
            "X": "1",
        ]
        let env = EnvironmentPolicy(extraPaths: ["/opt/homebrew/bin", "/x/bin"]).environment(from: base)
        #expect(env["NO_COLOR"] == "1" && env["SKILLCASK_AGENT"] == "0")
        #expect(env["CLICOLOR_FORCE"] == nil && env["CLAUDECODE"] == nil)
        #expect(env["PATH"] == "/usr/bin:/opt/homebrew/bin:/x/bin")
        #expect(env["HOME"] == "/Users/me" && env["X"] == "1")
    }

    @Test func overridesApplyExceptProtectedAndMalformedKeys() {
        let policy = EnvironmentPolicy(
            extraPaths: [],
            overrides: [
                "GITLAB_HOST": "git.example", "PATH": "/evil", "HOME": "/evil", "lower": "x", "1A": "x", "": "x",
            ])
        let env = policy.environment(from: ["PATH": "/usr/bin", "HOME": "/Users/me"])
        #expect(env["GITLAB_HOST"] == "git.example")
        #expect(env["PATH"] == "/usr/bin" && env["HOME"] == "/Users/me")
        #expect(env["lower"] == nil && env["1A"] == nil && env[""] == nil)
    }

    /// The Settings table can never export a token or undo what the policy sets: those keys are refused.
    @Test func tokensAndPolicyKeysCannotBeOverridden() {
        let forbidden = [
            "GITHUB_TOKEN", "GH_TOKEN", "COMPOSER_AUTH", "NO_COLOR", "SKILLCASK_AGENT", "CLICOLOR_FORCE", "CLAUDECODE",
            "AI_AGENT", "PATH", "HOME",
        ]
        let policy = EnvironmentPolicy(
            extraPaths: [], overrides: Dictionary(uniqueKeysWithValues: forbidden.map { ($0, "x") }))
        let env = policy.environment(from: ["PATH": "/usr/bin", "HOME": "/Users/me"])
        for key in forbidden {
            #expect(!EnvironmentPolicy.allowsOverride(key))
            #expect(env[key] != "x", "\(key) must not come from the table")
        }
        #expect(env["NO_COLOR"] == "1" && env["SKILLCASK_AGENT"] == "0")
        #expect(EnvironmentPolicy.allowsOverride("HTTPS_PROXY") && !EnvironmentPolicy.allowsOverride("SKILLCASK_HOME"))
    }

    /// One case per class of the table on `EnvironmentPolicy.forbidden`.
    @Test(arguments: [
        // Policy (policy.rs:16, 159-171).
        ("SKILLCASK_MIN_RELEASE_AGE", false), ("SKILLCASK_ALLOW_RANGES", false), ("SKILLCASK_PACKAGIST", false),
        ("SKILLCASK_GITHUB_REQUIRES", false), ("SKILLCASK_ALLOW_SOURCES", false), ("SKILLCASK_DENY_PATTERNS", false),
        // Hosts and credentials.
        ("SKILLCASK_GITHUB_API", false), ("GITHUB_API_URL", false), ("SKILLCASK_SKILLS_SH", false),
        ("SKILLCASK_GIT_CREDENTIALS", false), ("GITHUB_TOKEN", false), ("GH_TOKEN", false), ("COMPOSER_AUTH", false),
        ("COMPOSER_HOME", false), ("APPDATA", false), ("XDG_CONFIG_HOME", false), ("XDG_DATA_HOME", false),
        ("SKILLCASK_CA_FILE", false),
        // Behaviour and output.
        ("CI", false), ("NO_COLOR", false), ("SKILLCASK_AGENT", false), ("USERPROFILE", false),
        // Loader and git injection.
        ("DYLD_INSERT_LIBRARIES", false), ("LD_PRELOAD", false), ("GIT_ASKPASS", false), ("GIT_CONFIG_COUNT", false),
        ("SSH_ASKPASS", false), ("GCM_INTERACTIVE", false),
        // Unknown SKILLCASK_ names: a later CLI may read them as policy.
        ("SKILLCASK_FUTURE_POLICY", false),
        // Allowed.
        ("SKILLCASK_HOME", false), ("SKILLCASK_LINK_MODE", true), ("SKILLCASK_CACHE_DIR", true), ("WT_SESSION", true),
        ("HTTPS_PROXY", true), ("HTTP_PROXY", true), ("ALL_PROXY", true), ("NO_PROXY", true), ("GITLAB_HOST", true),
    ])
    func classification(key: String, allowed: Bool) {
        #expect(EnvironmentPolicy.allowsOverride(key) == allowed)
        let env = EnvironmentPolicy(extraPaths: [], overrides: [key: "x"]).environment(from: [:])
        #expect((env[key] == "x") == allowed)
    }

    @Test(arguments: [
        ("http://me:pw@proxy:3128", true), ("https://token@host/x", true), ("http://proxy:3128", false),
        ("me@example.com", false), ("~/Library/Caches/skillcask", false),
        ("ghp_abcDEF123", true), ("gho_x1", true), ("ghu_x1", true), ("ghs_x1", true), ("ghr_x1", true),
        ("github_pat_11AB_cd", true), ("glpat-xYz_1", true), ("Bearer ghp_abc", true), ("ghp_", false),
    ])
    func credentialsInURLs(value: String, found: Bool) {
        #expect(EnvironmentPolicy.hasCredentials(value) == found)
    }

    /// Display masks URL userinfo and token-shaped parts, nothing else.
    @Test func maskingHidesCredentialsOnly() {
        #expect(EnvironmentPolicy.masked("http://me:pw@proxy:3128") == "http://••••@proxy:3128")
        #expect(EnvironmentPolicy.masked("token ghp_abcDEF123 end") == "token ghp_•••• end")
        #expect(EnvironmentPolicy.masked("glpat-abc") == "glpat-••••")
        #expect(EnvironmentPolicy.masked("http://proxy:3128") == "http://proxy:3128")
    }

    /// A name that is still being typed towards a refused one never stores a value.
    @Test func valuesAreNotStoredForPrefixesOfRefusedNames() {
        #expect(!EnvironmentPolicy.mayStoreValue(name: "GITHUB_TOKE", value: "v"))
        #expect(!EnvironmentPolicy.mayStoreValue(name: "DYL", value: "v"))
        #expect(!EnvironmentPolicy.mayStoreValue(name: "GITHUB_TOKEN", value: "v"))
        #expect(!EnvironmentPolicy.mayStoreValue(name: "HTTPS_PROXY", value: "http://a:b@p"))
        #expect(EnvironmentPolicy.mayStoreValue(name: "HTTPS_PROXY", value: "http://p:3128"))
    }

    /// A shared source changes what the next read sees.
    @Test func sourceIsLive() {
        let source = EnvironmentSource(EnvironmentPolicy(extraPaths: []))
        source.policy.overrides["A"] = "1"
        #expect(source.policy.environment(from: [:])["A"] == "1")
    }

    @Test func emptyPathStillGetsTheInstallLocations() {
        let env = EnvironmentPolicy.default.environment(from: [:])
        #expect(env["PATH"] == EnvironmentPolicy.installLocations.joined(separator: ":"))
    }

    @Test(arguments: [
        ("A", true), ("A_B2", true), ("_X", true), ("a", false), ("2A", false), ("A-B", false), ("", false),
    ])
    func keyValidation(key: String, valid: Bool) {
        #expect(EnvironmentPolicy.isValidKey(key) == valid)
    }
}

@Suite struct LocatorTests {
    let executables: Set<String> = [
        "/opt/homebrew/bin/skillcask", "/Users/me/build/skillcask", "/app/Contents/MacOS/skillcask",
    ]

    func locator(bundled: String?) -> Locator {
        let executables = executables
        return Locator(
            policy: EnvironmentPolicy(extraPaths: ["/opt/homebrew/bin"]),
            bundled: bundled.map { URL(fileURLWithPath: $0) },
            isExecutable: { executables.contains($0.path) })
    }

    @Test func configuredPathWinsAndMustBeExecutable() throws {
        #expect(
            try locator(bundled: "/app/Contents/MacOS/skillcask").locate(configured: " /Users/me/build/skillcask ")
                == .configured(URL(fileURLWithPath: "/Users/me/build/skillcask")))
        #expect(throws: CLIError.binaryMissing(searched: ["/Users/me/nope"])) {
            try locator(bundled: nil).locate(configured: "/Users/me/nope")
        }
    }

    @Test func bundledThenSearchPath() throws {
        #expect(
            try locator(bundled: "/app/Contents/MacOS/skillcask").locate(configured: "")
                == .bundled(URL(fileURLWithPath: "/app/Contents/MacOS/skillcask")))
        #expect(
            try locator(bundled: "/app/missing").locate(configured: nil)
                == .onPath(URL(fileURLWithPath: "/opt/homebrew/bin/skillcask")))
    }

    @Test func nothingFoundListsWhereItLooked() {
        let locator = Locator(
            policy: EnvironmentPolicy(extraPaths: ["/nowhere/bin"]), bundled: nil, isExecutable: { _ in false })
        #expect {
            try locator.locate(configured: nil)
        } throws: { error in
            if case .binaryMissing(let searched) = error as? CLIError {
                searched.contains("/nowhere/bin/skillcask")
            } else {
                false
            }
        }
    }
}

@Suite struct SkillTextTests {
    @Test func frontMatterIsSplitAndUnquoted() {
        let text = SkillText.parse(
            "---\nname: notes\ndescription: \"Team \\\"notes\\\"\"\nlicense: 'it''s'\nbad line\n---\n# Notes\n\nBody.\n"
        )
        #expect(text.frontMatter.map(\.key) == ["name", "description", "license"])
        #expect(text.frontMatter.map(\.value) == ["notes", "Team \"notes\"", "it's"])
        #expect(text.body == "# Notes\n\nBody.\n" && !text.truncated)
        // Lines 1–6 are the front matter and its fences; `# Notes` is line 7.
        #expect(text.bodyStartLine == 7)
    }

    @Test func withoutFrontMatterTheWholeFileIsTheBody() {
        let text = SkillText.parse("# Title\n---\nnot front matter\n")
        #expect(text.frontMatter.isEmpty && text.body == "# Title\n---\nnot front matter\n")
        #expect(text.bodyStartLine == 1)
    }

    @Test(arguments: [
        ("a\u{1B}]52;c;eA==\u{07}b", "a<U+001B>]52;c;eA==<U+0007>b"),
        ("\u{200B}c\td", "<U+200B>c\td"),
        ("plain ü 👩‍💻", "plain ü 👩<U+200D>💻"),
        ("x\u{202E}y\u{E0041}", "x<U+202E>y<U+E0041>"),
        ("\r\n", "<U+000D>\n"),
    ])
    func shownEscapesControlAndInvisibleCharacters(input: String, expected: String) {
        #expect(SkillText.shown(input) == expected)
    }

    @Test func readCapsAt256KiB() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "skilltext-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: UInt8(ascii: "x"), count: SkillText.maxBytes + 10).write(to: url)
        let text = try SkillText.read(contentsOf: url)
        #expect(text.truncated && text.body.utf8.count == SkillText.maxBytes)
        try Data("---\nname: a\n---\nok\n".utf8).write(to: url)
        let small = try SkillText.read(contentsOf: url)
        #expect(!small.truncated && small.body == "ok\n" && small.frontMatter.first?.value == "a")
    }
}
