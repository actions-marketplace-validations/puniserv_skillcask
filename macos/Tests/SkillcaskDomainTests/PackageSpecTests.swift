import SkillcaskDomain
import Testing

/// The one spec grammar both the Add Skill field (`parse`: detection) and the Adopt sheet (`validate`: the CLI's
/// syntax checks) read: the three shapes `skillcask add` accepts, as `src/commands.rs` checks them.
@Suite struct PackageSpecTests {
    // MARK: - Detection (Add Skill)

    @Test(
        arguments: [
            ("jira", nil),
            ("jira triage", nil),
            ("Acme/Jira", nil),
            ("acme/", nil),
            ("netresearch/agent-jira-skill", "netresearch/agent-jira-skill"),
            ("acme/jira-triage@^4.2", "acme/jira-triage"),
            ("github:Owner/Repo/skill@v1", "owner/repo"),
            ("github:owner/repo", "owner/repo"),
            ("git:https://git.acme.example/team/sql-review.git@v2", "team/sql-review"),
            ("git:https://git.acme.example/sql-review.git", "https://git.acme.example/sql-review.git"),
            ("git:https://host.example/a/b/%2e%2E/repo", "a/repo"),
            ("git:https:\\\\host.example\\owner\\Repo.git", "owner/repo"),
        ] as [(String, String?)])
    func sourceShapes(text: String, package: String?) {
        #expect(PackageSpec.parse(text)?.package == package)
    }

    @Test func sourceKeepsItsPinAndSplitsTheGitRefAfterTheScheme() throws {
        let registry = try #require(PackageSpec.parse(" acme/lint@^2.0 "))
        #expect(registry.kind == .registry && registry.base == "acme/lint" && registry.pinned == "^2.0")
        #expect(registry.text(constraint: "^3.0") == "acme/lint@^2.0", "a typed pin wins over the rule")
        let github = try #require(PackageSpec.parse("github:owner/repo/skill@main"))
        #expect(github.kind == .github && github.base == "github:owner/repo/skill" && github.pinned == "main")
        let git = try #require(PackageSpec.parse("git:https://host.example/a/b.git@v1.2"))
        #expect(git.kind == .git && git.base == "git:https://host.example/a/b.git" && git.pinned == "v1.2")
        #expect(PackageSpec.parse("acme/lint")?.text(constraint: "^2.0") == "acme/lint@^2.0")
        #expect(PackageSpec.packageName(of: "github:anthropics/skills/pdf") == "anthropics/skills")
    }

    @Test func infoTargetDropsTheGitHubSkillPath() throws {
        let pinned = try #require(PackageSpec.parse("github:Owner/Repo/skill@v1"))
        #expect(pinned.infoTarget == "github:owner/repo@v1" && pinned.text == "github:Owner/Repo/skill@v1")
        #expect(pinned.skill == "skill")
        #expect(PackageSpec.parse("github:owner/repo")?.infoTarget == "github:owner/repo")
        #expect(PackageSpec.parse("acme/lint@^2")?.infoTarget == "acme/lint@^2")
    }

    // MARK: - Validation (Adopt)

    @Test(arguments: [
        ("acme/commit", PackageSpec.Kind.registry, "acme/commit"),
        ("acme/commit@^3.1", .registry, "acme/commit@^3.1"),
        ("  netresearch/agent-jira-skill  ", .registry, "netresearch/agent-jira-skill"),
        ("github:juliusbrussee/caveman", .github, "github:juliusbrussee/caveman"),
        ("github:Anthropics/Skills/pdf", .github, "github:Anthropics/Skills/pdf"),
        ("github:anthropics/skills/frontend-design@v1", .github, "github:anthropics/skills/frontend-design@v1"),
        ("git:https://git.acme.example/acme/sql-review.git", .git, "git:https://git.acme.example/acme/sql-review.git"),
        (
            "git:https://git.acme.example/team/sql-review.git@v0.9", .git,
            "git:https://git.acme.example/team/sql-review.git@v0.9"
        ),
    ])
    func acceptsTheThreeShapes(text: String, kind: PackageSpec.Kind, spec: String) throws {
        let parsed = try PackageSpec.validate(text).get()
        #expect(parsed.kind == kind && parsed.text == spec)
    }

    @Test(arguments: [
        ("", PackageSpec.Problem.empty),
        ("   ", .empty),
        ("caveman", .packageName),
        ("Acme/Commit", .packageName),
        ("acme/commit@", .packageName),
        ("acme/-commit", .packageName),
        ("acme/com..mit", .packageName),
        ("GitHub:a/b", .packageName),
        ("acme/commit extra", .packageName),
        ("github:caveman", .github),
        ("github:a/b/Bad_Skill", .github),
        ("github:a/b@", .github),
        ("github:@v1", .github),
        ("github:a/b c", .github),
        ("git:http://git.acme.example/a/b.git", .gitURL),
        ("git:https://git.acme.example/onlyrepo", .gitURL),
        ("git:https://token@git.acme.example/a/b", .gitURL),
        ("git:https://git.acme.example/a/b?ref=x", .gitURL),
        ("git:https://git.acme.example/a/b@", .gitURL),
        ("git:sql-review", .gitURL),
        ("git:", .gitURL),
    ])
    func refusesWhatTheCLIRefuses(text: String, problem: PackageSpec.Problem) {
        #expect(PackageSpec.validate(text) == .failure(problem))
    }

    @Test func packageNamesFollowTheManifestRule() {
        #expect(PackageSpec.isPackageName("acme/commit"))
        #expect(PackageSpec.isPackageName("a1/b.c_d-e"))
        #expect(!PackageSpec.isPackageName("acme"))
        #expect(!PackageSpec.isPackageName("acme/commit/x"))
        #expect(!PackageSpec.isPackageName("acme/commit."))
    }

    // MARK: - The CLI mirror

    /// The CLI's own checks, case by case, so a change on either side shows here. Each row names the Rust function
    /// whose behaviour it mirrors (`src/commands.rs` `add`, `add_github`, `git_spec`; `src/git.rs` `check_url`,
    /// `name_of`; `src/manifest.rs` `valid_package_name`; `src/skill.rs` `valid_name`). `detected` is the Add
    /// Skill reading: a registry spec only when valid, any non-empty `github:`/`git:` text. Every accepted spec is
    /// detected as the same spec, and the lock name it detects is `name_of`'s / `add_github`'s.
    @Test(arguments: [
        // add + valid_package_name
        ("acme/commit", true, true), ("acme/commit@3.1.0", true, true), ("a.b/c_d-e", true, true),
        ("acme/jira-triage@^4.2", true, true), ("acme", false, false), ("jira triage", false, false),
        ("acme/Commit", false, false), ("acme/commit_", false, false), ("_acme/commit", false, false),
        ("acme/co..mmit", false, false), ("acme/commit/extra", false, false), ("acme/", false, false),
        ("acme/commit@", false, false), ("GitHub:a/b", false, false),
        // add_github: owner/repo lowercased, optional skill (valid_name), optional @ref
        ("github:Owner/Repo", true, true), ("github:owner/repo/skill-1", true, true),
        ("github:owner/repo@main", true, true), ("github:Owner/Repo/skill@v1", true, true),
        ("github:owner", false, true), ("github:owner/repo/", false, true), ("github:owner/repo/Skill", false, true),
        ("github:owner/repo/-skill", false, true), ("github:owner/repo/a_b", false, true),
        ("github:owner/repo@", false, true), ("github:", false, false),
        // git_spec + check_url + name_of
        ("git:https://host.example/owner/repo.git", true, true), ("git:https://host.example/owner/repo/", true, true),
        ("git:https://dev.azure.com/org/project/_git/repo", true, true),
        ("git:https://host.example/owner/repo@v1", true, true),
        ("git:https://git.acme.example/team/sql-review.git@v2", true, true),
        ("git:http://host.example/owner/repo", false, true), ("git:https://host.example/repo", false, true),
        ("git:https://host.example/_git/repo", false, true), ("git:https://user@host.example/owner/repo", false, true),
        ("git:https://host.example/owner/repo?x=1", false, true),
        ("git:https://host.example/owner/repo#frag", false, true),
        ("git:https://host.example/owner/re%20po", false, true),
        ("git:https://git.acme.example/sql-review.git", false, true), ("git:", false, false),
        // url::Url::parse (WHATWG) under check_url and name_of: `\\` is `/`, dot segments resolve, the scheme
        // takes any case and any run of slashes, an empty userinfo is no credential
        ("git:https:\\\\host.example\\owner\\repo", true, true),
        ("git:https://host.example/owner\\repo.git", true, true),
        ("git:https://host.example/owner/x/../repo", true, true),
        ("git:https://host.example/a/b/%2e%2E/repo", true, true),
        ("git:https://host.example/o/r/.", true, true), ("git:HTTPS://host.example/owner/repo", true, true),
        ("git:https:host.example/owner/repo", true, true), ("git:https:///host.example/owner/repo", true, true),
        ("git:https://@host.example/owner/repo", true, true), ("git:https://host.example:8443/owner/repo", true, true),
        ("git:https://host.example/owner/repo/..", false, true), ("git:https://host.example/a/%2e", false, true),
        ("git:https://:@host.example/owner/repo", false, true), ("git:https://host.example/a/b?", false, true),
        // url's host and port parsers: ports up to 65535, a numeric last label must be IPv4, IPv6 in brackets,
        // percent-encoded hosts (refused here outright; see HTTPSURL's "Not mirrored")
        ("git:https://host.example:65535/owner/repo", true, true), ("git:https://host.example:/owner/repo", true, true),
        ("git:https://host.example:08443/owner/repo", true, true),
        ("git:https://host.example:65536/owner/repo", false, true),
        ("git:https://host.example:12a/owner/repo", false, true),
        ("git:https://1.2.3.4/owner/repo", true, true), ("git:https://0x7f.1/owner/repo", true, true),
        ("git:https://4294967295/owner/repo", true, true), ("git:https://1.2.3./owner/repo", true, true),
        ("git:https://256.0.0.1/owner/repo", false, true), ("git:https://1.2.3.4.5/owner/repo", false, true),
        ("git:https://999999999999/owner/repo", false, true), ("git:https://4294967296/owner/repo", false, true),
        ("git:https://a.1/owner/repo", false, true), ("git:https://ex.09/owner/repo", false, true),
        ("git:https://[::1]/owner/repo", true, true), ("git:https://[zz]/owner/repo", false, true),
        ("git:https://ho%00st/owner/repo", false, true), ("git:https://ho%20st/owner/repo", false, true),
        ("git:https://ho%2fst/owner/repo", false, true),
    ])
    func mirrorsTheCLIChecks(spec: String, accepted: Bool, detected: Bool) {
        switch PackageSpec.validate(spec) {
        case .success(let valid):
            #expect(accepted, "the CLI refuses \(spec)")
            #expect(PackageSpec.parse(spec) == valid, "Add Skill reads \(spec) differently")
            #expect(PackageSpec.isPackageName(valid.package), "\(spec) locks as \(valid.package)")
        case .failure:
            #expect(!accepted, "the CLI accepts \(spec)")
        }
        #expect((PackageSpec.parse(spec) != nil) == detected, "Add Skill detection of \(spec)")
    }
}
