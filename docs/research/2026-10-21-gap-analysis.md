# skillcask feature gap analysis

Date: 2026-10-21. Code: `0.4.1` (`560d1b3`). Status: research, no code changes.

## Status on 2026-10-28 (0.9.4)

Done from the Top 10: `diff` and `update --diff` (1), invisible character warnings (2, D23),
`validate` (3), `outdated --strict` (5, D25), HTTP retries with `Retry-After` (6), `info` with
`why` (7, D32), `abandoned` (8), a hint on conflict markers in `skills.lock` and the CI action
(10, D33). From the queue after it: `--json` for `status` and `outdated` (D32), git sources other
than GitHub (D30, D36), `audit` with SARIF (D34). Still open: `publish --json` (4) and sha256
verification in the npm wrapper (9; the README still points to Homebrew or a release archive).
The tables below describe the state on 2026-10-21; `file:line` references point at 0.4.1.

## Scope and method

skillcask compared with mature package managers (Composer, npm, pnpm, Yarn 4, Bun, Cargo, uv, pip)
and with agent skill tools (Vercel Skills CLI, Claude Code plugins, the Codex skill installer,
`netresearch/composer-agent-skill-plugin`, qvr, skillfold, grimoire, openskills, skillport, skild,
skillkit, skills-npm). Facts about other tools come from their official documentation or from
their README and sources on GitHub, checked on 2026-10-21; each fact has its link. The state of
skillcask comes from `src/` (file:line) and the specifications in `docs/specs/`.

Limits: documentation pages were read through a summarizing tool, so open the link before quoting
verbatim. Items that could not be confirmed are marked "unconfirmed". Tool versions move fast
(npm 12, pnpm 11/12, Composer 2.10): setting defaults are given for the documented version on the
day of the check.

Legend:

- **Cost**: S up to a few days, M up to two weeks, L more or a large new dependency.
- **Recommendation**: *do*, *consider*, *don't*.
- **Conflict**: a non-goal of the v1 spec (`NG`), a decision (`D1`…`D19`), a non-goal of a partial
  spec, or an invariant from `AGENTS.md` (no scripts from packages, `install` = exactly the lock,
  no telemetry).

## Starting point: what skillcask has today

Commands (`src/main.rs:81-140`): `init`, `add`, `remove`, `install [--frozen]`, `update [pkg…]`,
`outdated`, `status`, `doctor [--fix]`, `search`, `auth set|remove`, `publish`, external
`skillcask-<cmd>` from `PATH`. Global flags: `-v`, `-g`, `--agent`, `--max-download`,
`--max-unpacked`, `--max-files`.

Manifest `skills.toml`, lock `skills.lock` (version, commit reference, `dist-sha256`,
`tree-sha256` per skill, `requires` in version 2), `min-release-age` cooldown (3 days by default),
`allow-sources` with policy layers (D18), dependencies from `requires:` in `SKILL.md` (D16), global
scope and aliases (D13), two output modes (D19), token storage in the git credential helper (D17),
a static Composer repository from `publish` (D9, D12, D14).

---

## 1. CLI commands

| Gap | What others do | State in skillcask | Conflict | Value | Cost | Recommendation |
|---|---|---|---|---|---|---|
| **`outdated` for CI**: exit code, filters, dependencies | Composer `outdated --strict` (exit ≠ 0), `--direct`, `--minor-only`, `--format=json` ([doc](https://getcomposer.org/doc/03-cli.md#outdated)); `composer skills:outdated --strict` in the netresearch plugin ([README](https://github.com/netresearch/composer-agent-skill-plugin)); `pnpm outdated --format json` ([doc](https://pnpm.io/cli/outdated)); `uv tree --outdated` ([doc](https://docs.astral.sh/uv/reference/cli/#uv-tree--outdated)) | Always exit 0, manifest entries only, no dependencies (`src/commands.rs:1309-1340`) | Non-goal `outdated` for dependencies (`docs/specs/2026-10-20-skill-dependencies.md:29`) | High: a scheduled CI job can tell there is something to update without parsing a table | S | **Do**: `--strict` (exit 1), `via <requirer>` rows for dependencies; lift the non-goal with a separate decision |
| **`why <skill>`**: where a skill comes from | `composer why` / `why-not` ([doc](https://getcomposer.org/doc/03-cli.md#depends-why)), `npm explain` ([doc](https://docs.npmjs.com/cli/v12/commands/npm-explain)), `pnpm why` ([doc](https://pnpm.io/cli/why)), `cargo tree -i` ([doc](https://doc.rust-lang.org/cargo/commands/cargo-tree.html)), `uv tree --invert` | `status` shows `via <requirer>` (`src/commands.rs:1358-1361`); no lookup by skill name rather than package | — | Medium: with D16 and `rename` a skill's name does not say which package it came from | S | **Do** as part of `info` or a separate `why` |
| **`info`/`show <pkg>`**: versions, skills in the package, description, `requires`, license | `composer show` ([doc](https://getcomposer.org/doc/03-cli.md#show-info)), `cargo info` ([doc](https://doc.rust-lang.org/cargo/commands/cargo-info.html)), `bun info --json` ([doc](https://bun.com/docs/pm/cli/info)) | None. Before `add` there is no way to see which skills a GitHub repository has (the `it has: …` error shows only after a wrong name, `src/commands.rs:231-234`) | — | Medium-high: choosing `skills = [...]` without guessing | S-M | **Do** (`info <pkg>[@ver]`, locally from the lock, over the network with `--remote`) |
| **`list`** of installed skills | `npx skills list --json` ([commands.md](https://github.com/vercel-labs/skills/blob/main/docs/commands.md)), `composer show`, `pnpm list` | `status` plays this role, but exits 1 on problems | — | Low | S | **Don't**: `status` is enough; an alias at most |
| **`diff`**: what an update changes in a skill's text | `bun pm diff` ([doc](https://bun.com/docs/pm/cli/pm)); `npm diff` is on npm's command list ([list](https://docs.npmjs.com/cli/v11/commands), details unconfirmed) | None. `update` prints `updated a/b 1.0 -> 1.1` (`src/commands.rs:1272`); a reviewer sees only changed hashes in `skills.lock` | — | **Very high**: a skill is a prompt; reviewing its text before merge is the only real control (the README's Security section says so outright for commit dates) | S-M | **Do**: `diff [pkg] [--to <ver>]`, a unified diff of the skill files between the locked version and the candidate; optionally `update --diff` |
| **`--dry-run`** for `add`/`update`/`remove` | Composer `require/update/install --dry-run` ([doc](https://getcomposer.org/doc/03-cli.md)), `cargo update --dry-run` ([doc](https://doc.rust-lang.org/cargo/commands/cargo-update.html)), `uv lock --dry-run`, `uv sync --dry-run` ([doc](https://docs.astral.sh/uv/reference/cli/#uv-lock--dry-run)), `pip install --dry-run` | None; `add` resolves before writing and changes nothing on error (v1 spec, command table), but on success it writes and installs at once | — | Medium: an agent or CI can check what would change | M | **Consider**; `update --dry-run` gives the most (together with `diff`) |
| **`validate`/lint `SKILL.md`** | `claude plugin validate` ([doc](https://code.claude.com/docs/en/plugin-marketplaces)), `skillport validate --json` ([README](https://github.com/gotalab/skillport)), `skild validate` ([README](https://github.com/Peiiii/skild)), `skills-ref validate` ([repo](https://github.com/agentskills/agentskills/tree/main/skills-ref)); Agent Skills spec: `name` 1-64 characters and equal to the directory name, `description` required, 1-1024 characters, `compatibility` ≤ 500 ([spec](https://agentskills.io/specification)); `composer validate --strict` ([doc](https://getcomposer.org/doc/03-cli.md#validate)) | `publish` silently skips a `SKILL.md` without `name` or `version` (`src/publish.rs:69`), checks the name and `requires:`; it does not check `description`, lengths, or that the name matches the directory | — | High for authors and monorepo CI: a typo in the frontmatter today gives "nothing published" | S | **Do**: `validate [paths]` with the spec's rules; `publish` warns about skipped files |
| **Shell completion** | `composer completion` ([doc](https://getcomposer.org/doc/03-cli.md#bash-completions)), `pnpm completion` ([doc](https://pnpm.io/completion)), `uv generate-shell-completion` ([doc](https://docs.astral.sh/uv/reference/cli/#uv-generate-shell-completion)) | None | New dependency (`clap_complete`), small and without `unsafe` on the runtime path (to check when adding) | Low-medium | S | **Consider** (cheap, but needs a dependency decision) |
| **`exec`/`run`/scripts** | `composer run-script`, `npm exec`/`npx`, `pnpm dlx`, `uvx`, `bunx` | None, by design | Invariant "no package code", NG v1 | — | — | **Don't**. External `skillcask-<cmd>` commands (`src/main.rs:232-251`) cover extensibility without package code |
| **`use`** (a skill's prompt without installing) | `npx skills use <src>@<skill>` ([commands.md](https://github.com/vercel-labs/skills/blob/main/docs/commands.md)) | None | Against the goal: bypasses the lock and hashes | Low | S | **Don't** |
| **`bump`**: raise constraint lower bounds to the locked version | `composer bump` ([doc](https://getcomposer.org/doc/03-cli.md#bump)), `uv add --bounds` | None; `add` without a constraint writes `^major.minor` | — | Low | S | **Consider** later |
| **Interactive `update`** | `composer update --interactive`, `pnpm update -i` ([doc](https://pnpm.io/cli/update)), `yarn upgrade-interactive` ([doc](https://yarnpkg.com/cli)), `bun update -i` | None; the only prompt is rename (`src/commands.rs:655-675`) | — | Low: usually a handful of packages | M | **Don't** |
| **`self-update`** | `composer self-update` ([doc](https://getcomposer.org/doc/03-cli.md#self-update-selfupdate)), `uv self update`, `pnpm self-update`, `bun upgrade` | None; `install-updater = false` in `dist-workspace.toml` | Consistent with D1 (Homebrew, npm, cargo, archives) | Low; an updater is one more binary download channel to secure | S | **Don't** |
| **`config`** | `composer config`, layered `cargo` config ([doc](https://doc.rust-lang.org/cargo/reference/config.html)), user/system/project `uv.toml` ([doc](https://docs.astral.sh/uv/concepts/configuration-files/)) | `status` prints the effective policy and its source (`src/commands.rs:1404-1406`) | — | Low | S | **Don't** add a separate command |
| **Environment `doctor`** (git, symlink permissions, network reach) | `npm doctor` ([doc](https://docs.npmjs.com/cli/v12/commands/npm-doctor)), `composer diagnose` | `doctor` checks only the project: links, gitignore block, hashes (`src/commands.rs:1418-1516`) | — | Low-medium: Windows without symlink permission and a missing git are common causes of questions | S | **Consider** a few environment checks in `doctor -v` |

## 2. Manifest and lock

| Gap | What others do | State in skillcask | Conflict | Value | Cost | Recommendation |
|---|---|---|---|---|---|---|
| **Merge conflicts in the lock** | pnpm resolves conflicts in `pnpm-lock.yaml` on `pnpm install` ([doc](https://pnpm.io/git)); Composer: a conflict only in `content-hash` is fixed by `update --lock`, automatically since 2.9 ([doc](https://getcomposer.org/doc/articles/resolving-merge-conflicts.md), [blog](https://blog.packagist.com/composer-2-9/)) | The lock has no timestamps other than `released` and is sorted (v1 spec, `skills.lock`); drift is computed semantically instead of a `content-hash` (`src/commands.rs:929-956`), so conflicts are rare. A file with `<<<<<<<` markers fails to parse (`src/lock.rs:130`) with no hint | — | Medium: two PRs adding different skills touch neighbouring `[[package]]` entries | S (hint) / M (merging) | **Do** the hint: detect the markers and say "take one side, run `skillcask install`", since `install` resolves missing manifest entries again. Automatic merging: **consider** |
| **Platforms, agent version** (`engines`, `os`/`cpu`, MSRV) | npm `engines` and `os`/`cpu` ([doc](https://docs.npmjs.com/cli/v11/configuring-npm/package-json)), Cargo `rust-version` in the resolver ([doc](https://doc.rust-lang.org/cargo/reference/resolver.html)); the Agent Skills spec has a `compatibility` field (text) ([spec](https://agentskills.io/specification)) | None | — | Low: `compatibility` is free text and cannot be resolved | — | **Don't** in the resolver; `info` can show `compatibility` |
| **`abandoned`/deprecation field** | Composer schema `abandoned` (bool or a replacement) ([doc](https://getcomposer.org/doc/04-schema.md#abandoned)), returned by the Packagist API ([apidoc](https://packagist.org/apidoc)); Composer 2.10 `policy.abandoned` ([doc](https://getcomposer.org/doc/06-config.md)); `npm deprecate`, `cargo yank` ([doc](https://doc.rust-lang.org/cargo/commands/cargo-yank.html)) | Version metadata is read without `abandoned` (`src/registry.rs:127-170`) | — | Medium: an author can point users to a successor | S | **Do**: a warning in `add`/`update`/`outdated`; in `publish`, frontmatter `deprecated:` → `abandoned` in the metadata |
| **Lock format versioning** | `uv.lock` has a schema version and `revision` ([doc](https://docs.astral.sh/uv/concepts/resolution/#lockfile-versioning)) | `version = 1/2`, an older version refuses `2` (`src/lock.rs:132-134`) | — | Present | — | No change |
| **Constraints and stability** | Composer `minimum-stability`, `prefer-stable` ([doc](https://getcomposer.org/doc/articles/versions.md)); uv `--prerelease` with per-package variants ([doc](https://docs.astral.sh/uv/concepts/resolution/#pre-release-handling)) | Composer semantics, pre-releases only when the constraint names a stability (v1 spec, Resolution points 3-4) | — | Enough | — | No change |

## 3. Dependency resolution

| Gap | What others do | State in skillcask | Conflict | Value | Cost | Recommendation |
|---|---|---|---|---|---|---|
| **Backtracking / solver** | Cargo backtracking ([doc](https://doc.rust-lang.org/cargo/reference/resolver.html)), uv PubGrub with conflict explanations ([doc](https://docs.astral.sh/uv/reference/internals/resolver/)) | One pass, constraint intersection, at most 50 rounds (`src/deps.rs:82`, `src/commands.rs:886-925`) | Non-goal (`docs/specs/2026-10-20-skill-dependencies.md:28`) | Low: skill graphs are shallow, one version per name | L | **Don't** until a real conflict shows up in practice |
| **Overrides / resolutions** | npm `overrides`, pnpm `overrides`, Yarn `resolutions` ([doc](https://yarnpkg.com/configuration/manifest)), uv `override-dependencies` ([doc](https://docs.astral.sh/uv/concepts/resolution/#dependency-overrides)), Cargo `[patch]` ([doc](https://doc.rust-lang.org/cargo/reference/overriding-dependencies.html)) | A manifest entry wins over the source, plus `skills` and `rename` of dependencies (`docs/specs/2026-10-20-skill-dependencies.md`, Resolving section); a constraint imposed by a requirer cannot be loosened | — | Low-medium: a skill author may pin a dependency too narrowly | M | **Consider** `override = "^2.0"` on a manifest entry when such a case comes up |
| **Local paths** (`path`, `link:`, `workspace:`) | Composer `path` repository with a symlink ([doc](https://getcomposer.org/doc/05-repositories.md#path)), Cargo `path` ([doc](https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html)), `bun link` / `link:` ([doc](https://bun.com/docs/pm/cli/link)), uv `path` sources ([doc](https://docs.astral.sh/uv/concepts/projects/dependencies/)); Vercel `add ./local` ([README](https://github.com/vercel-labs/skills/blob/main/README.md)) | Project skills in `[agents] local` (`.skills/`) and hand-written ones in `.agents/skills` are linked (v1 spec, Installing and linking); no `path` entry for a package from another directory, from which an author could test a skill with dependencies | — | Medium for monorepo authors: today the loop is `publish` + `update` | M | **Consider** `{ path = "../skills/x" }` without locked hashes (like Composer `path`), refused under `--frozen` |
| **Workspaces** | Cargo workspaces ([doc](https://doc.rust-lang.org/cargo/reference/workspaces.html)), pnpm/npm/Yarn/Bun workspaces, uv workspace ([doc](https://docs.astral.sh/uv/concepts/projects/workspaces/)); Composer has none | `find_root` takes the nearest `skills.toml` (`src/project.rs:27`) | — | Low: agents read skills from the repository root (Codex: from cwd up to the root, [doc](https://learn.chatgpt.com/docs/build-skills)) | L | **Don't** |
| **Patching** local changes to a package | `pnpm patch` ([doc](https://pnpm.io/cli/patch)), `yarn patch`, `bun patch` ([doc](https://bun.com/docs/pm/cli/patch)) | A changed skill is `modified` in `status`, `install` restores the original (`src/commands.rs:1369-1373`) | A patch is data, not code, so the invariant holds; the hash must cover the result | Low-medium: a fork or a project skill is usually better | M | **Consider** later; a project skill in `.skills/` is the simpler workaround today |

## 4. Registries and publishing

| Gap | What others do | State in skillcask | Conflict | Value | Cost | Recommendation |
|---|---|---|---|---|---|---|
| **`publish --json`** (list of new zips to upload) | `uv version --output-format json`, `npm publish --json` (npm has a global `--json`, [doc](https://docs.npmjs.com/cli/v12/using-npm/config)) | `publish` prints `<state> <package> <version>` lines (`src/publish.rs:204`, `233-235`); a CI job uploading zips parses text | Non-goal "JSON output" (`docs/specs/2026-10-20-cli-output.md:40`) | High for monorepo CI; already requested | S | **Do**: lift the non-goal for this command (new decision), print `[{package, version, state, zip, url, sha256}]` |
| **Git repositories other than GitHub** (GitLab, any git, SSH) | Vercel: GitLab, Azure Repos, any git URL, a local path, an archive ([README](https://github.com/vercel-labs/skills/blob/main/README.md)); Composer `vcs` type ([doc](https://getcomposer.org/doc/05-repositories.md)); Claude Code marketplace: `git-subdir`, `url`, `archive` with `sha256` ([doc](https://code.claude.com/docs/en/plugin-marketplaces)) | Only Composer and the GitHub API (D2, D11) | NG v1 "plain git repositories" | Medium: GitLab is covered by a Composer registry, but needs publishing | L (git without the git binary) / M (GitLab API similar to GitHub) | **Consider** a GitLab API source like D11 once requests come in; any git: **don't** (D1, a missing git in CI should not break `install`) |
| **Mirror / source replacement** | Cargo `[source] replace-with` ([doc](https://doc.rust-lang.org/cargo/reference/source-replacement.html)), uv multiple indexes and mirrors ([doc](https://docs.astral.sh/uv/concepts/indexes/)) | `SKILLCASK_GITHUB_API` and the `url` of a `github` repository (`docs/specs/2026-10-20-source-policy.md`, Default sources); `dist.url` in the lock is absolute | — | Medium for networks cut off from the internet | M | **Consider** URL prefix rewriting (`mirror = { "https://api.github.com/" = "https://proxy/…" }`) in `config.toml`; hashes still verify the content |
| **Repositories from user config** | Cargo `[registries]` in `~/.cargo/config.toml` ([doc](https://doc.rust-lang.org/cargo/reference/registries.html)), user/system `uv.toml` | Only `[policy]` from `config.toml` | Non-goal (`docs/specs/2026-10-20-source-policy.md:23-24`) | Medium for organizations: one private registry in every project | M | **Consider** after the first rollout in an organization |
| **Signatures / provenance of skill packages** | npm `--provenance` and `audit signatures` ([doc](https://docs.npmjs.com/generating-provenance-statements)), npm trusted publishing ([doc](https://docs.npmjs.com/trusted-publishers)), crates.io ([doc](https://crates.io/docs/trusted-publishing)), `uv publish` uploads PEP 740 attestations ([doc](https://docs.astral.sh/uv/guides/package/)); qvr: `provenance`, signature verification, `trust pin` of commit authors ([README](https://github.com/try-agora/qvr)) | Only the skillcask binary has attestations (v1 spec, Distribution); skill packages have hashes in the lock, no author identity | Composer registries have no signatures | Medium; grows once a skill registry becomes a target | L (Sigstore verification is a large dependency) | **Consider** later; the cheapest step: record the GitHub commit author and verification (`verification.verified` from the API) in the lock, with no crypto of our own |
| **Publishing a single package to a Composer registry** | `cargo publish --dry-run` ([doc](https://doc.rust-lang.org/cargo/commands/cargo-publish.html)), `uv publish --check-url` ([doc](https://docs.astral.sh/uv/reference/cli/#uv-publish--check-url)) | "skillcask has no part in it" (v1 spec, Publishing) | D9 | Low | — | **Don't** |
| **Own hosted registry / UI** | skild (own registry, `publish`), grimoire (OCI registry, [README](https://github.com/grimoire-rs/grimoire)) | None | NG v1 "hosted registry or web UI" | — | L | **Don't** |

## 5. Security

| Gap | What others do | State in skillcask | Conflict | Value | Cost | Recommendation |
|---|---|---|---|---|---|---|
| **Scanning skill text** (prompt injection, invisible Unicode, exfiltration) | Vercel shows a table of partner audits on `add`, results on [skills.sh/audits](https://skills.sh/audits) ([src/add.ts](https://github.com/vercel-labs/skills/blob/main/src/add.ts)); qvr has a built-in scanner (15 categories, including invisible Unicode), stores the result in the lock and exports SARIF ([README](https://github.com/try-agora/qvr)); skillkit `scan` ([README](https://github.com/rohitg00/skillkit)); Bun `[install.security] scanner` ([doc](https://bun.com/docs/runtime/bunfig)) | None; file names are checked (v1 spec, Security), the text is not | A remote scan over the network would be telemetry; running a scanner is the user's code, not the package's (allowed) | **High**: a skill's text is input to an agent with permissions on the repository | S (Unicode) / M (hook) | **Do** in two steps: (1) built-in, deterministic warnings about bidi, zero-width and Unicode tag characters in a skill's text files on `add`/`update`/`diff`; (2) **consider** `policy.scanner = "<cmd>"` run on the unpacked directory before the lock is written (the user's command, not the package's). Prompt injection heuristics: **don't** in our own code; effectiveness is low and false positives high |
| **Advisories (`audit`)** | `composer audit` with the Packagist API ([doc](https://getcomposer.org/doc/03-cli.md#audit), [API](https://packagist.org/apidoc)), Composer 2.9+ blocks versions with an advisory on update ([blog](https://blog.packagist.com/composer-2-9/)); `npm audit`, `pnpm audit`, `bun audit` ([doc](https://bun.com/docs/pm/cli/audit)); `uv audit` with OSV ([doc](https://docs.astral.sh/uv/reference/cli/#uv-audit)) | None | — | Low today: practically no advisories for `ai-agent-skill` packages; grows with the ecosystem | M | **Consider**: `audit` through Packagist's `api/security-advisories` for Packagist packages; for GitHub through OSV/GHSA later |
| **Cooldown** | pnpm `minimumReleaseAge` (1440 min by default since v11, [doc](https://pnpm.io/settings/dependency-resolution)), Yarn `npmMinimalAgeGate` (1w by default, [doc](https://yarnpkg.com/configuration/yarnrc)), Bun `minimumReleaseAge` ([doc](https://bun.com/docs/runtime/bunfig)), npm `min-release-age` (no default, [doc](https://docs.npmjs.com/cli/v12/using-npm/config)), uv `exclude-newer` with relative time and per package ([doc](https://docs.astral.sh/uv/concepts/resolution/#dependency-cooldowns)), pip `--uploaded-prior-to` ([doc](https://pip.pypa.io/en/stable/cli/pip_install/#cmdoption-uploaded-prior-to)), Composer `policy.cooldown` (documented, release unclear: [doc](https://getcomposer.org/doc/06-config.md), [blog](https://blog.packagist.com/composer-2-10-release/)) | Present: 3 days by default, per repository (D15), GitHub push times, availability date in the error and in `outdated` (v1 spec, Resolution point 5) | — | — | — | No change. Only a per-package exception is missing (`minimumReleaseAgeExclude`, `exclude-newer-package`): **consider** when someone has to take a security fix quickly |
| **Source policy for organizations** | Claude Code `strictKnownMarketplaces`, `blockedMarketplaces` in managed settings ([doc](https://code.claude.com/docs/en/plugins/org)); pnpm `blockExoticSubdeps` ([doc](https://pnpm.io/settings/dependency-resolution)); npm 12 `allow-git` defaults to `none` ([doc](https://docs.npmjs.com/cli/v12/using-npm/config)) | `allow-sources` + `enforce` + environment variables, checked against the lock too (D18); GitHub in dependencies only with `github-requires` (D16) | Non-goal `/etc` (`docs/specs/2026-10-20-source-policy.md:24`) | Enough for a project and a user; a fleet of machines needs `config.toml` distributed | S | **Consider** a system path (`/etc/skillcask/config.toml`) only when administrators ask |
| **Source consent (trust prompt)** | `composer skills:trust` in the netresearch plugin ([README](https://github.com/netresearch/composer-agent-skill-plugin)), Composer `allow-plugins` ([doc](https://getcomposer.org/doc/06-config.md#allow-plugins)) | None, by design | NG v1 "Trust prompts" | — | — | **Don't**: an entry in `skills.toml` goes through code review |
| **Scripts from packages** | npm 12 blocks dependency scripts by default, `approve-scripts` ([doc](https://docs.npmjs.com/cli/v12/commands/npm-approve-scripts)); pnpm `allowBuilds`, `strictDepBuilds` ([doc](https://pnpm.io/settings/build)); Bun `trustedDependencies` ([doc](https://bun.com/docs/pm/lifecycle)); Claude Code plugins carry hooks, MCP servers and `bin/` ([doc](https://code.claude.com/docs/en/plugins/components)) | Never | Invariant | — | — | A strength of skillcask, see below |
| **Sandbox** | No counterpart in package managers; agents have their own sandboxes | Not applicable: skillcask runs nothing | — | — | — | **Don't** |
| **npm wrapper verification** | dist-generated wrapper; uv and pip verify package hashes with `--require-hashes` ([doc](https://pip.pypa.io/en/stable/cli/pip_install/#cmdoption-require-hashes)) | README: the npm wrapper "does not check a checksum itself" | — | Medium: `npx skillcask install --frozen` in CI is a popular path | S-M | **Do**: verify the downloaded binary's sha256 in the wrapper (the sums are already published), or ship binaries as per-platform `optionalDependencies` |

## 6. Performance

| Gap | What others do | State in skillcask | Conflict | Value | Cost | Recommendation |
|---|---|---|---|---|---|---|
| **Download cache** | Composer cache with TTL and GC ([doc](https://getcomposer.org/doc/06-config.md)), pnpm's content-addressable store ([doc](https://pnpm.io/motivation)), uv's global cache with linking ([doc](https://docs.astral.sh/uv/concepts/cache/)) | None: every missing skill is a new download (`src/commands.rs:90-113`); untouched skills are skipped (`installed_ok`, `src/commands.rs:813-815`) | — | Medium: worktrees, fresh clones, many projects with the same skills, the GitHub limit of 60 unauthenticated requests (applies to the API, not zipballs) | M | **Consider**: a zip cache keyed by `dist-sha256` in the user's cache directory; the hash is verified on read, so a poisoned cache changes nothing |
| **Offline** | `--offline` in Cargo, uv, pnpm, Bun ([uv](https://docs.astral.sh/uv/reference/cli/#uv-lock--offline), [Bun](https://bun.com/docs/pm/cli/install)); Yarn offline mirror ([doc](https://yarnpkg.com/features/caching)); skillfold `check` offline ([README](https://github.com/byronxlg/skillfold)) | `status`, `doctor` work without a network; `install` needs the network for missing skills | — | Low-medium, depends on the cache | S after the cache | **Consider** together with the cache |
| **Parallelism** | `COMPOSER_MAX_PARALLEL_HTTP` (12 by default, [doc](https://getcomposer.org/doc/03-cli.md)), uv 50 parallel downloads ([doc](https://docs.astral.sh/uv/reference/settings/#concurrent-downloads)), Cargo HTTP/2 multiplexing | Sequential (`src/commands.rs:508-542`, `src/commands.rs:1267-1276`) | — | Low-medium: skills are small, but `update` with a dozen GitHub entries is dozens of requests in a row | S-M (`std::thread::scope`, no new dependency) | **Consider** for downloads and metadata requests |
| **Request retries** | uv and Composer retry network errors (details unconfirmed in the docs) | One attempt, 300 s timeout (`src/http.rs:212`, `src/http.rs:239`); 5xx and 429 end the command (`src/http.rs:268`) | — | Medium in CI: one GitHub 502 breaks a pipeline | S | **Do**: 2-3 retries with backoff for connection errors, 429 and 5xx, honouring `Retry-After` |

## 7. UX/DX

| Gap | What others do | State in skillcask | Conflict | Value | Cost | Recommendation |
|---|---|---|---|---|---|---|
| **`--json` everywhere** | npm global `--json`; Composer `--format=json` in `show`, `outdated`, `audit`, `licenses` ([doc](https://getcomposer.org/doc/03-cli.md)); `cargo metadata` ([doc](https://doc.rust-lang.org/cargo/commands/cargo-metadata.html)); uv `--output-format json` in some commands ([doc](https://docs.astral.sh/uv/reference/cli/)); Vercel `list --json`, `add --json` | Agent mode: tab-separated lines with problems only (D19, `src/ui.rs:110`) | Non-goal (`docs/specs/2026-10-20-cli-output.md:40`) | Medium: agent mode covers agents; scripts and bots prefer a stable schema | M | **Consider** three commands instead of "everywhere": `publish`, `outdated`, `status`, with a versioned schema (like `cargo metadata --format-version 1`). Needs the non-goal changed by a new decision |
| **More agents in `targets`** | Vercel supports about 79 agents; many read the shared `.agents/skills` (Codex, Cursor, Gemini CLI, Copilot, OpenCode and others per [docs/agents.md](https://github.com/vercel-labs/skills/blob/main/docs/agents.md)); skillkit 46 agents ([README](https://github.com/rohitg00/skillkit)) | The `.agents/skills` store plus links in `.claude/skills` and `.junie/skills` (`src/manifest.rs:14`); `targets` configurable | — | Low-medium: agents that read `.agents/skills` already work; the rest need one line in `targets` | S | **Do** a table in the docs, "agent → reads `.agents/skills` / which target to add"; presets in code: **don't** |
| **Quiet mode `-q`** | Composer `-q`, uv `-q`/`-qq` ([doc](https://docs.astral.sh/uv/reference/cli/)), npm `loglevel` | None; agent mode is terse | — | Low | S | **Consider** |
| **New skill template** | `npx skills init` ([README](https://github.com/vercel-labs/skills/blob/main/README.md)), `skild init`, `npm init <initializer>` ([doc](https://docs.npmjs.com/cli/v12/commands/npm-init)) | `init` creates only `skills.toml` (`src/commands.rs:1014-1024`) | — | Low-medium for authors | S | **Consider** `init --skill <name>`: `.skills/<name>/SKILL.md` with `name`, `description`, `version` |
| **Interactive choice in `search`/`add`** | Vercel `find` in fzf style, agent and skill selection in `add` | `search` prints a list (`src/commands.rs:1518-1534`) | Interactivity clashes with CI and agent mode | Low | M | **Don't** |
| **Documented error codes** | Yarn `YN####` and `yarn explain` ([doc](https://yarnpkg.com/advanced/error-codes)) | 6 exit codes (`src/error.rs:3-7`) and a `hint:` line | — | Low | — | **Don't** |

## 8. CI and agents

| Gap | What others do | State in skillcask | Conflict | Value | Cost | Recommendation |
|---|---|---|---|---|---|---|
| **CI action** | grimoire `setup-grimoire` GitHub Action ([README](https://github.com/grimoire-rs/grimoire)); skill scanners offer actions and pre-commit hooks | `CI` forces `--frozen` (`src/main.rs:153-155`, `192`); installed in CI through the dist script, npm or an archive | — | Medium: a pinned version + sha256 check in one step instead of a copied script | S | **Do** a `setup-skillcask` action (version, sha256, cache) and a GitLab CI example in the README |
| **Update bots** | Renovate and Dependabot know `composer.lock`, `Cargo.lock`, `uv.lock` (unconfirmed for this analysis) | They do not know `skills.toml`/`skills.lock` | — | Medium: without a bot, skill updates do not happen | S (docs) | **Do** a recipe: a scheduled `skillcask update` job + `diff` + opening a PR; `outdated --strict` as the gate |
| **A command for agents** | skillport MCP ([README](https://github.com/gotalab/skillport)), skillkit MCP and REST server | Agent mode (D19) | — | Low: an agent runs the CLI | M | **Don't** add an MCP server; **consider** a skill describing how to use skillcask, published from the repository |
| **Index in `AGENTS.md`** for agents without skill support | the netresearch plugin generates a registry in `AGENTS.md` ([README](https://github.com/netresearch/composer-agent-skill-plugin)), openskills `sync` ([README](https://github.com/numman-ali/openskills)) | None | — | Low-medium, shrinking as native skill support spreads | S | **Consider** as an external `skillcask-agents-md` command, not in the core |

## 9. Ecosystem and extensions

| Gap | What others do | State in skillcask | Conflict | Value | Cost | Recommendation |
|---|---|---|---|---|---|---|
| **In-process plugins** | Yarn plugins loaded at startup with the full API ([doc](https://yarnpkg.com/features/extensibility)), Composer plugins | External `skillcask-<cmd>` from `PATH`, installed by the user (`src/main.rs:232-251`) | Invariant: packages do not ship commands | — | — | **Don't** do more than today |
| **Artifacts other than skills** (rules, agents, MCP) | grimoire, OpenPackage, skillfold also manage rules and MCP servers ([grimoire](https://github.com/grimoire-rs/grimoire), [OpenPackage](https://github.com/enulus/OpenPackage), [skillfold](https://github.com/byronxlg/skillfold)) | Skills only | MCP servers are code: invariant | Medium for rules (data), none for MCP | L | **Don't** do MCP; rules: **consider** only once agents' formats settle |
| **Skills from npm packages** | skills-npm ([README](https://github.com/antfu/skills-npm)), Vercel `experimental_sync` | None | D2 (one backend plus GitHub) | Low | M | **Don't** |
| **SBOM / licenses** | `npm sbom` CycloneDX/SPDX ([doc](https://docs.npmjs.com/cli/v12/commands/npm-sbom)), `uv export --format cyclonedx1.5` ([doc](https://docs.astral.sh/uv/reference/cli/#uv-export--format)), `composer licenses --format=json`, `pnpm licenses` ([doc](https://pnpm.io/cli/licenses)) | None; the `license` frontmatter field is not read | — | Low-medium for compliance teams | S-M | **Consider** `licenses` (from frontmatter and Composer metadata) before a full SBOM |
| **Skill usage telemetry** | qvr `audit` builds spans from an agent's session history ([README](https://github.com/try-agora/qvr)); Vercel sends telemetry by default ([src/telemetry.ts](https://github.com/vercel-labs/skills/blob/main/src/telemetry.ts)) | None | NG v1, D10 | — | — | **Don't** |

---

## Top 10

Ordered by value to cost, with supply-chain security first, since that is the main reason the tool
exists.

| # | What | Cost | Why now |
|---|---|---|---|
| 1 | `diff [pkg]` and `update --diff`: a unified diff of a skill's text between the locked and the new version | S-M | Reviewing the text is the only control for prompts; today a reviewer sees only hashes in the lock |
| 2 | Warnings about invisible Unicode characters (bidi, zero-width, tags) in skill files on `add`/`update`/`diff`/`validate` | S | An attack invisible in the diff and in review; deterministic, offline, no telemetry |
| 3 | `validate [paths]` per the Agent Skills spec, `publish` warns about skipped `SKILL.md` files | S | Today a typo in the frontmatter gives a silent "nothing published" |
| 4 | `publish --json` (a new decision lifting the non-goal for this command) | S | Already requested; CI parses text |
| 5 | `outdated --strict` (exit 1) and dependencies in `outdated` | S | A gate for scheduled jobs and update bots |
| 6 | HTTP request retries (connection, 429, 5xx, `Retry-After`) | S | One registry 502 breaks a pipeline with `install --frozen` |
| 7 | `info <pkg>` (skills in the package, versions, description, `requires`, license, `abandoned`) answering "why" | S-M | Choosing `skills = [...]` without guessing; the source of every skill visible |
| 8 | Reading `abandoned` from Composer metadata and `deprecated:` in `publish` | S | Cheap, a Composer standard, warns about dead skills |
| 9 | sha256 verification of the binary in the npm wrapper | S-M | The weakest link in distributing a tool that promises hash verification |
| 10 | A hint on merge conflicts in `skills.lock` + a CI recipe (`setup-skillcask` action, scheduled `update`) | S | The most common friction in teams; both are mostly documentation |

Next in line: a download cache with `--offline`, parallel downloads, a `policy.scanner` hook,
`--json` for `status`/`outdated`, a `path` source for authors, mirrors by URL prefix.

## What not to do, on purpose

- Running anything from packages: `exec`, scripts, hooks, plugins from packages, MCP servers
  (invariant).
- Trust prompts (NG v1): the decision is the entry in `skills.toml` after code review.
- Telemetry, including "anonymous" telemetry and remote audits through a vendor's network (NG v1,
  D10).
- A backtracking solver, workspaces, interactive `update`, `self-update`, an own registry: the
  cost is out of proportion to shallow skill graphs, or it contradicts D1/D2.
- Arbitrary git repositories: they would need a git binary in CI or an implementation of the
  protocol.

## Where skillcask is better

1. **A lock that is a gate.** Commit, `dist-sha256` and `tree-sha256` per skill, checked on every
   `install`, exit 4 on a mismatch (D6). Vercel pins a branch or tag and does not check
   `computedHash` on `experimental_install` ([src/install.ts](https://github.com/vercel-labs/skills/blob/main/src/install.ts), lock format: [src/local-lock.ts](https://github.com/vercel-labs/skills/blob/main/src/local-lock.ts)); Claude Code plugins
   do not describe a project lock; the Codex skill installer has no lock and no update ([SKILL.md](https://github.com/openai/skills/blob/main/skills/.system/skill-installer/SKILL.md)).
2. **No package code, no exceptions.** npm 12, pnpm and Bun had to add allowlists for scripts;
   Claude Code plugins carry hooks, MCP and `bin/` run with the user's permissions
   ([doc](https://code.claude.com/docs/en/plugins/components)). skillcask has nothing to switch off.
3. **Cooldown on by default and source-aware.** 3 days, overridable per repository (D15), push
   times from the Activity API for GitHub branches, the availability date in the error and in
   `outdated`. Composer and npm have cooldown off by default ([Composer](https://getcomposer.org/doc/06-config.md), [npm](https://docs.npmjs.com/cli/v12/using-npm/config)).
4. **Source policy enforced on the lock too.** `allow-sources` with layers and `enforce` blocks a
   source during resolution and on `install --frozen` (D18); a blocked repository gets no request.
   Protection against dependency confusion by pinning to the repository in the lock, with
   Packagist always last, similar to `first-index` in uv ([doc](https://docs.astral.sh/uv/concepts/indexes/#searching-across-multiple-indexes)).
5. **One static binary.** Vercel needs Node ≥ 22.20, the netresearch plugin PHP and Composer, the
   Codex installer Python. skillcask works in a repository in any language (D1).
6. **No telemetry.** Vercel sends telemetry by default ([src/telemetry.ts](https://github.com/vercel-labs/skills/blob/main/src/telemetry.ts)).
7. **Agent mode.** Terse, colourless output with problems only, detected from `AI_AGENT` and
   `CLAUDECODE` (D19). None of the compared package managers has an equivalent.
8. **Tokens in the system store by default.** The git credential helper (Keychain, Credential
   Manager, libsecret) with no new dependency (D17); `uv auth` writes to a plain text file by
   default ([doc](https://docs.astral.sh/uv/concepts/authentication/cli/)), and so does Cargo's
   `cargo:token` ([doc](https://doc.rust-lang.org/cargo/reference/registry-authentication.html)).
9. **Merge conflicts avoided by design.** Drift is computed semantically instead of one
   `content-hash`, which in Composer conflicts on every parallel change
   ([doc](https://getcomposer.org/doc/articles/resolving-merge-conflicts.md)).
10. **Hardened archives on three systems.** Rejects names invalid on Windows, case collisions and
    Unicode normalization collisions, symlinks outside the skill, with size and file count limits
    (v1 spec, Security).
11. **Name collisions resolved explicitly.** `rename` with the hash of the renamed copy, warnings
    about shadowing by personal skills (D13). Codex does not merge duplicate names
    ([doc](https://learn.chatgpt.com/docs/build-skills)).
12. **`requires` in the lock checked against `SKILL.md`.** Editing the lock alone cannot add a
    package the manifest did not ask for (D16, `src/commands.rs:480-506`).
13. **Publishing with no infrastructure.** Deterministic zips, immutable versions, `--inline` mode
    for hosting without `/` in file names (D9, D12, D14).
