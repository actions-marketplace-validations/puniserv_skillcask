# Competitor deep check (2026-10-26)

Re-checks the alternatives critique in `docs/specs/2026-10-19-skillcask-v1.md` against current source.
Every claim cites the file or page read. Clones were taken 2026-10-26; commit shas below.

## 1. vercel-labs/skills (`npx skills`, skills.sh)

Checked: `vercel-labs/skills@a80e4c9` (= tag `v1.7.4`, 2026-10-19, `npm view skills` latest = 1.7.4,
published 2026-10-19T20:35Z). The spec's `b465908` is a merge commit on 2026-10-19 between `v1.7.2`
(`671e8c3`, 2026-10-09) and `v1.7.3`; `v1.7.3`/`v1.7.4` only promote `sync` and touch docs/help
(`git log v1.7.2..v1.7.4`). Paths below are at `a80e4c9`.

### (a) Facts

- **Runtime**: Node `>=22.20.0` (`package.json` `engines`), bins `skills` and `add-skill`.
  CI runs `ubuntu-latest` and `windows-latest` (`.github/workflows/ci.yml:17`); macOS not in CI.
  On Windows agent links are directory junctions (`src/installer.ts:290`).
- **Commands** (`src/cli.ts:357-437`): `add` (aliases `a`, `install`, `i`), `use <pkg>@<skill>`
  (prints a prompt / spawns an agent without installing, `src/use.ts:360`), `remove` (`rm`, `r`),
  `list` (`ls`), `find` (`search`, `f`, `s`), `init`, `sync` (= `experimental_sync`),
  `experimental_install`, `check` / `update` / `upgrade`.
- **`add` flags** (`src/cli.ts:175-185`, `docs/commands.md` "Options"): `-g/--global`,
  `-a/--agent <agents>` (`'*'` = all), `-s/--skill <names>` (`'*'` = all), `-l/--list`, `-y/--yes`,
  `--copy`, `--metadata <json>` (attached to the install telemetry event), `--subagent` (Eve),
  `--all` (= `--skill '*' --agent '*' -y`), `--full-depth`, `--json`. No `--branch` flag: a ref is
  given as a URL fragment `owner/repo#<ref>[@<skill>]` (`src/source-parser.ts:285-311`); Azure
  Repos take `?version=GB<branch>|GT<tag>` (`src/source-parser.ts:126-136`).
- **Sources** (`docs/commands.md` "Source Formats"; `src/source-parser.ts` types `github`,
  `gitlab`, `git`, `local`, `download`, `well-known`): GitHub shorthand/URL/tree path, GitLab,
  Azure Repos, any git URL incl. SSH, local path, direct `SKILL.md` or archive URL (`download`),
  Notion pages, and "well-known" HTTP discovery (`/.well-known` index, schema
  `https://schemas.agentskills.io/discovery/0.2.0/schema.json`, `src/providers/wellknown.ts:1`).
  `sync` also reads npm packages in `node_modules` and a `package.json` `skills` field
  (grammar from `antfu/skills-npm` SPEC, `src/skills-field.ts:5`). No tarball registry, no
  semver ranges anywhere (grep for `semver` in `src/` returns nothing).
- **Private sources**: uses the user's git credential helper, then `gh repo clone`, then SSH;
  `GITHUB_TOKEN`/`GH_TOKEN` for API (`docs/commands.md` "Private Repositories"). No registry auth
  because there is no registry.
- **Blob fast path**: for GitHub repos of owners `vercel`, `vercel-labs`, `heygen-com`,
  `remotion-dev` (and `zapier/connectors` self-hosted) files come from `skills.sh/api/download`
  snapshots instead of git (`src/add.ts:1165-1186`, `src/blob.ts:1-60`). The server-supplied
  `hash` becomes the lock's `computedHash` (`src/blob.ts:695`, `src/add.ts:1390`); it is
  recorded, not checked.
- **Project lock** `skills-lock.json` (`src/local-lock.ts:15-64`), `version: 1`, per skill:
  `source`, `sourceUrl?`, `ref?` (branch or tag *as typed*), `sourceType`, `skillPath?`,
  `version?` (npm sources only), `via?`, `computedHash` (sha256 over sorted path+bytes,
  `computeSkillFolderHash`, `src/local-lock.ts:150`), `subagents?`, `wellKnownDigest?`.
  No resolved commit field. A corrupt or older-version lock is silently treated as empty
  (`readLocalLock`, `src/local-lock.ts:78-104`).
- **Global lock** `~/.agents/.skill-lock.json` v3 (`src/skill-lock.ts:1-60`): `skillFolderHash` =
  GitHub tree sha "fetched via GitHub Trees API by the telemetry server", plus timestamps.
- **Restore from lock**: `skills experimental_install` (`src/install.ts`) groups entries by
  source and calls `installFromSource(parseSource(source))` / `runAdd` with `ref` only. It
  never reads `computedHash`. It installs only into `.agents/skills/` (universal agents), not
  agent-specific dirs; npm entries go through `sync` (`docs/commands.md` "Restore skills from the
  project lock file"). A failing source sets exit code 1 but others continue.
- **computedHash use**: grep shows it is read in exactly one place, `src/update.ts:938`, to skip
  reinstalling an unchanged skill during `update`. Not compared on `experimental_install`, `add`
  or `sync`.
- **Commit pinning**: only manual. If the user writes a full 40-hex sha as the fragment ref,
  `cloneRepo` falls back to `cloneAtSha` (`src/git.ts:295-323`, `isCommitSha` at `:30`) and the
  lock stores that sha as `ref`. Without it the lock stores a branch/tag (or nothing = default
  branch).
- **`check` vs `update`**: `case 'check': case 'update': case 'upgrade': await runUpdate(...)`
  (`src/cli.ts:420-423`). Since commit `3d0f855` (2026-04-11, PR #913) the separate `runCheck`
  is gone, so **`skills check` reinstalls changed skills** although `docs/commands.md:166-171`
  still says "Check installed skills for available updates without reinstalling them". `update`
  re-clones `ref`, hashes, and re-runs `skills add` for changed skills (`src/update.ts:880-960`).
  No dry-run, no diff, no non-zero exit on "updates available".
- **Agents**: 79 entries in `src/agents.ts` (incl. `universal`), e.g. claude-code, codex, cursor,
  github-copilot, gemini-cli, kiro-cli, opencode, junie, windsurf, zed, openclaw. Canonical copy
  in `.agents/skills/<name>`; agent dirs get symlinks (`--copy` for copies); agents whose
  `skillsDir` is `.agents/skills` are "universal" (`getUniversalAgents`, `src/agents.ts:878`).
- **Telemetry**: on by default; `DISABLE_TELEMETRY` or `DO_NOT_TRACK` disables it
  (`src/telemetry.ts:86`). GET to `https://www.skills.sh/tele/t` with version, CI flag, detected
  agent, event (`install`, `remove`, `update`, `find` incl. query, `experimental_sync`)
  (`src/telemetry.ts:1-60,143-178`). Install events for GitHub sources are sent only when GitHub
  confirms the repo is public; non-GitHub sources are always sent (`src/add.ts:2174-2205`,
  `docs/troubleshooting.md:40`). skills.sh install counts come from this telemetry (leaderboard,
  e.g. `find-skills` 4.0M installs, https://skills.sh/ fetched 2026-10-26).
- **Security audit**: on `add` the CLI fetches `https://www.skills.sh/tele/audit` for public
  GitHub repos and prints a table with columns Gen (Gen Agent Trust Hub), Socket, Snyk
  (`src/add.ts:150-200,1792-1803`). Display only, 3 s timeout, never blocks
  (`src/telemetry.ts:105-137`). Dashboard: https://skills.sh/audits ("Combined security audit
  results from Gen Agent Trust Hub, Socket, and Snyk"). No local prompt-injection scanner in
  the CLI.
- **Well-known digests**: v0.2.0 discovery entries carry `digest: sha256:...`; the archive is
  rejected if bytes do not match the index (`src/providers/wellknown.ts:376,511`). The digest
  and the archive come from the same host, and the lock's `wellKnownDigest` is not re-checked on
  restore.
- **Code execution**: no package scripts run. Spawns `git`, `gh`, and for `use` the chosen agent
  CLI (`src/git.ts`, `src/use.ts`). `sync` does not run `npm install` (`docs/commands.md`
  "Restore ...": "does not install npm packages"); the docs suggest a `prepare` script calling
  `skills experimental_sync -y`.

### (b) Lock/integrity verdict

Pins commit: **no** (only if the user types a sha as ref). Verifies hash: **no** on install;
hash used only as an "unchanged" shortcut in `update`. Frozen/CI mode: **no**
(`experimental_install` is best effort; `check` mutates). Semver: **no**.

### (c) What it has that skillcask lacks

- Breadth: 79 agent targets, well-known HTTP discovery, Notion/direct-URL/archive sources,
  Azure Repos, npm-shipped skills via `package.json` `skills` field and `node_modules`.
- `skills find` against a hosted search index with install counts; `skills use` (one-off prompt
  without installing).
- Third-party risk ratings (Gen, Socket, Snyk) shown at install time.
- `--json` machine output on `add`/`list`.

### (d) Corrections to the spec critique

- Version/commit: update to `v1.7.4` (`a80e4c9`, 2026-10-19). The substance did not change
  between `b465908` and `a80e4c9` (`src/install.ts` differs only in one comment).
- Still true: `experimental_install` re-fetches from `ref`, ignores `computedHash`; no semver;
  `update` takes newest; Node required; telemetry on by default.
- Sharpen: "no CI drift check" -> also `skills check` is an alias of `update` and modifies the
  install (`src/cli.ts:420`), contrary to its own docs.
- Add nuance: a sha can be pinned by hand (`owner/repo#<40-hex>`); for vercel-owned repos content
  comes from skills.sh snapshots, not git, and the snapshot hash is trusted as-is.
- "Needs Node": now specifically Node >= 22.20.
- D11 says "skills.sh itself is not used: its API needs a Vercel OIDC token". Not true on
  2026-10-26: `GET https://skills.sh/api/search?q=react&limit=2` returned 200 with `installs`
  counts anonymously (Algolia-backed, response includes a `rate_limit` timing), and
  `GET https://skills.sh/api/download/vercel-labs/agent-skills/vercel-react-best-practices`
  returned the file snapshot. The CLI calls both without auth (`src/find.ts:87-93`,
  `src/blob.ts:469`). The API is undocumented, so relying on it is still a choice, but the
  stated reason is stale.

## 2. Tessl

Checked 2026-10-26. CLI `@tessl/cli` 0.118.0 (npm modified 2026-10-23; docs changelog "Latest
version = 0.118.0", 2026-10-23). Docs read as Markdown via `https://docs.tessl.io/<page>.md`.

### (a) Facts

- **What it is**: commercial platform (registry, governance, evals, observability, code review,
  automations, agent); "context as code" where skills, rules and docs are "versioned, reviewed, and
  rolled out with the same rigor as code dependencies" (https://docs.tessl.io/overview/readme.md).
  FAQ positions it against skills.sh, which has "no built-in versioning or dependency management"
  (https://docs.tessl.io/support/faqs.md).
- **License/runtime**: CLI is proprietary: `LICENSE.md` in the npm tarball @0.118.0 reads
  "Copyright 2025 Tessl. All rights reserved. This software is proprietary". The npm package is a
  32 KB installer (`bin/tessl.js`) that downloads a versioned native binary into
  `~/.local/share/tessl/versions` and auto-updates (`TESSL_AUTO_UPDATE_INTERVAL_MINUTES`)
  (`npm pack @tessl/cli@0.118.0`). Needs Node 22.17+; Mac/Linux/Windows
  (https://docs.tessl.io/support/supported-platforms.md); Windows uses junctions since 0.106.0
  (https://docs.tessl.io/changelog-cli.md).
- **Packaging**: the unit is a plugin, `.tessl-plugin/plugin.json` with required `name`
  (`workspace/name`) and `version` (semver); bundles skills, rules, commands, hooks (`hooks`,
  per-agent `nativeHooks`) and `.mcp.json` (https://docs.tessl.io/reference/configuration.md).
  Older `tile.json` migrated (https://docs.tessl.io/use/tile-to-plugin-migration.md).
- **Manifest** `tessl.json`: `{"name","mode","region","dependencies":{"ws/plugin":{"version":"1.0.0"}}}`,
  local deps `"source":"file:./..."` (configuration.md;
  https://docs.tessl.io/distribute/repository-plugins.md).
- **No lockfile**: neither configuration.md nor the CLI changelog mentions `tessl.lock` or any
  content hash; the docs' Q&A endpoint says `tessl.json` is "a dependency manifest, not a
  separate lockfile" and that no frozen flag or hash verification is documented.
- **Sources** (https://docs.tessl.io/reference/cli-commands.md): registry
  `workspace/plugin[@version]` (default latest), GitHub (`github:o/r`, URL, SSH, `/tree/<branch>/<path>`),
  `file:<path>`, commit pins `github:<repo>@<sha>` (0.73.0, 2026-03-16). Only GitHub for git.
  Git sources "pinned to commit SHAs for version stability" (0.61.1); 0.61.4 fixed installing trunk
  instead of "the commit sha in `tessl.json`" (changelog-cli.md).
- **Install flags**: `--global/-g`, `--skill`, `--yes`, `--watch-local`, `--accept-warnings`,
  `--strict` (fail if a version is too new for age policy, not a frozen mode), `--agent`.
- **Modes**: content in `.tessl/plugins/<ws>/<plugin>/`, linked into agent dirs. "Managed" mode
  gitignores it and reinstalls from registry; "vendored" mode (default for new projects) commits
  it and "Ensures reproducible builds" (configuration.md). Reproducibility = committing content.
- **Updates**: `tessl outdated` (current / compatible / latest); `tessl update` applies compatible
  updates, majors need `--force`
  (https://docs.tessl.io/tutorials/using-tessl-as-a-package-manager.md); `tessl version
  patch|minor|major` (0.85.0). Range syntax in `tessl.json`: unverified (docs show exact versions).
- **Publish**: `tessl skill import` writes `plugin.json`; `skill publish`/`plugin publish` with
  `--workspace`, `--public`, `--bump`, `--dry-run`; private by default; lint on publish
  (cli-commands.md). Async publication checks; a policy-blocked version "is unavailable while
  blocked and cannot be overwritten"
  (https://docs.tessl.io/creating-skills-and-plugins/publish-and-update.md).
- **Private registry**: workspaces private by default, org/workspace roles, SAML SSO, EU region
  (https://docs.tessl.io/distribute/permissions.md, https://docs.tessl.io/administrators/eu-region.md).
  SaaS only; Enterprise lists "self-hosted options" (https://tessl.io/pricing).
- **Dependencies**: none between plugins (no `dependencies` in `plugin.json` field list,
  configuration.md).
- **Security**: `tessl review run security` = server-side Snyk scan, `--fail-on
  low|medium|high|critical` as CI gate, needs login (cli-commands.md). Install policies at
  org/workspace/project (tightest wins): severity warn/block, source restriction (git on/off,
  host/org allowlist), **minimum release age**
  (https://docs.tessl.io/tutorials/protecting-against-insecure-skills.md). Release/commit-age
  enforcement since 0.82.0 (2026-06-05): registry falls back to newest old-enough version or
  blocks; git resolves to "the most recent commit old enough" (changelog-cli.md).
- **Agents**: `--agent` accepts `claude-code`, `cursor`, `gemini`, `antigravity`, `codex`,
  `openhands`, `openclaw`, `copilot`, `copilot-vscode`, `agents`, `tessl-agent` (cli-commands.md).
  Also writes `.mcp.json` and `RULES.md`/`AGENTS.md` wiring for its own MCP server.
- **Runs code**: yes, plugin hooks are written into agent hook configs; plugins ship MCP servers;
  eval `setup.sh` off by default (configuration.md).
- **Telemetry**: `shareUsageData` defaults `true`, opt-out `tessl config set shareUsageData false`;
  data "may include conversations, code snippets and file contents" (configuration.md,
  https://docs.tessl.io/legal/sharing-usage-data.md). Login (GitHub/Google) needed for publish,
  review, evals (https://docs.tessl.io/introduction-to-tessl/set-up-tessl/installation.md);
  anonymous install of public packages: unverified.
- **Pricing**: Free $0 (1,000 credits, 1 workspace), Team $100/month, Enterprise custom;
  "Publishing and installing plugins is always free" (https://tessl.io/pricing, 2026-10-26).

### (b) Lock/integrity verdict

Pins commit: **yes** for GitHub sources (sha in `tessl.json`); registry pins exact version.
Verifies hash: **no** (none documented). Frozen: **no**; vendored mode instead. An org commit-age
policy can change which commit resolves.

### (c) What it has that skillcask lacks

Org-wide install policy (severity block, source allowlist); server-side Snyk scan with CI gate;
publish-time gates where blocked versions cannot be overwritten; review scores and evals; org
inventory of skills across repos (`tessl inventory import`); majors held back unless `--force`;
`--bump` on publish; `--watch-local`; hosted private workspaces with SSO.

### (d) Spec corrections

The spec does not mention Tessl; it should. Tessl already ships semver with compatible updates,
commit-pinned git sources and a release-age cooldown. It still lacks content hashes and a
fail-on-drift install, runs plugin hooks/MCP, has telemetry on by default and a proprietary SaaS
registry. Suggested Problem bullet: "Tessl (proprietary CLI 0.118.0): semver registry, git sources
pinned to commit, org release-age policy and Snyk gates, but `tessl.json` has no content hashes,
no frozen install (reproducibility only by vendoring `.tessl/plugins/`), plugins ship hooks and MCP
servers, telemetry on by default."
## 3. Claude Code plugins and agent-native skill conventions

Docs checked 2026-10-26; source repos at the commits shown.

### 3.1 Claude Code plugins

#### (a) Facts

- **Marketplace**: a repo/dir with `.claude-plugin/marketplace.json` (`name`, `owner`,
  `plugins[]`, each with `name`, `source`); `claude plugin marketplace add <owner>/<repo>`, then
  `claude plugin install <plugin>@<marketplace>`; private repos supported
  (https://code.claude.com/docs/en/plugin-marketplaces).
- **Plugin sources**: relative path, `github` (`repo`, `ref`, `sha`), `url` (any git), `git-subdir`
  (sparse), `archive` (`url`, `sha256`; v2.1.224+), `npm`, `command` (output of a command run
  locally). `sha` = "a full 40-character lowercase commit SHA. When you set both `ref` and `sha`,
  Claude Code checks out `sha`"; for `archive` with `sha256`, "Claude Code refuses a download that
  doesn't match" (https://code.claude.com/docs/en/plugins/marketplace-reference.md, "Plugin
  sources"). Marketplace sources themselves take `ref`/`path`/`sparsePaths` but no `sha` (same page),
  so the catalog follows a branch/tag head.
- **Version**: `plugin.json` `version` is "a version string, not checked against semver. Setting
  it pins the plugin to that version until you change it"
  (https://code.claude.com/docs/en/plugins-reference). Resolution order: manifest `version` >
  marketplace entry `version` > derived (git: commit sha shortened to 12; archive: sha256 shortened
  to 12). It keys update detection and the cache dir
  `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`; a fixed `"version": "1.0.0"` keeps
  users on the cached copy "however many commits they push"
  (https://code.claude.com/docs/en/plugins/loading.md, "Versions and updates").
- **State**: per user, `~/.claude/plugins/known_marketplaces.json` (`source`, `installLocation`,
  `lastUpdated`, `autoUpdate`) and `installed_plugins.json` (`scope`, `installPath`, `version`).
  No project lock (loading.md).
- **Settings**: `enabledPlugins` maps `plugin@marketplace` to a boolean only; scopes user, project
  (`.claude/settings.json`), local, managed; managed `false` blocks install at every scope
  (https://code.claude.com/docs/en/settings-reference). `extraKnownMarketplaces` in a repo's
  settings registers marketplaces after the trust dialog; each machine still installs
  (https://code.claude.com/docs/en/plugins/org.md, "Require plugins per repository").
- **Auto-update**: on by default for Anthropic and claude.ai marketplaces, off for others;
  disabled by `DISABLE_AUTOUPDATER`/`DISABLE_UPDATES`/`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`;
  `command` sources re-run every session; orphaned versions deleted after 14 days (loading.md).
- **Dependencies**: `plugin.json` `dependencies` `{name, marketplace, version}` with npm-semver
  ranges, resolved to the highest tag `<plugin>--v<version>`; "If you force-move a tag to a
  different commit, the next install fetches that commit's content"; `claude plugin tag` creates
  tags (https://code.claude.com/docs/en/plugins/dependencies.md).
- **Runs code**: "A Claude Code plugin you install can execute arbitrary code on your machine with
  your user privileges" (hooks, monitors, JS mods, stdio MCP/LSP, `bin/` on PATH), outside the
  sandbox; "When auto-update is on ... the files you reviewed can change on disk"
  (https://code.claude.com/docs/en/plugins/security.md). A plugin's own npm deps install from its
  lockfile with exact versions, frozen resolution, `--ignore-scripts` (loading.md, "Limits on the
  dependency install").
- **Enterprise**: managed `strictKnownMarketplaces` (alias `allowedMarketplaces`) allowlist,
  `blockedMarketplaces` (checked first), `disableCommandPluginSources`, `allowManagedHooksOnly`,
  `strictPluginOnlyCustomization`; release channels = separate marketplaces at different refs;
  allowlist works per marketplace, not per entry (org.md). `CLAUDE_CODE_PLUGIN_SEED_DIR` seeds CI
  images (org.md, "Seed containers and CI").
- **Telemetry**: OTel events `claude_code.plugin_installed`/`plugin_loaded`; Enterprise Analytics
  API reports per-plugin installs and invocations (org.md, "Audit and review").
- **Standalone skills**: `.claude/skills/<name>/SKILL.md` (project, nested and parent dirs up to
  repo root), `~/.claude/skills/`, managed dir; symlinked folders supported; precedence enterprise >
  personal > project; `.agents/skills` not read (https://code.claude.com/docs/en/skills).
- **Quality tools**: `claude plugin eval` (v2.1.269+) runs graded eval cases against a no-plugin
  baseline, CI-gateable (https://code.claude.com/docs/en/plugin-evals); `/skill-doctor`
  (v2.1.252+) reports per-skill context cost and usage (skills page, "Find unused skills");
  `claude plugin validate [--strict]` (plugins-reference).

#### (b) Lock/integrity verdict

Pins commit: **author-side only** (`sha` in the marketplace entry); consumers cannot pin,
`enabledPlugins` has no version, resolved sha prefix lives in per-user `installed_plugins.json`.
Verifies hash: **only `archive` + `sha256`**. Frozen: **no** (closest: seed dir + auto-update
off). Semver: only for plugin-to-plugin deps via tags.

#### (c) What it has that skillcask lacks

Managed source allow/blocklists; release channels; per-catalog auto-update; bundling with
agents, hooks, MCP/LSP; `userConfig` with secret storage; behavioural evals and usage/cost
reporting; archive sources with sha256 and `headersHelper` auth; seed dir for offline CI.

#### (d) Implications for the spec

No project lock exists, so a repo cannot freeze plugin content for all contributors. Do not claim
plugins "never pin": marketplace authors can set `sha`, and `archive` verifies sha256. Plugins
run code, which keeps skillcask's data-only invariant a differentiator. D5's `.claude/skills` link
remains required.

### 3.2 Agent-native directories and installers

| Agent | Project dirs | User dirs | Built-in installer | Lock / pin |
|---|---|---|---|---|
| Codex | `.agents/skills` (cwd up to repo root) | `~/.agents/skills`, `/etc/codex/skills`, bundled | `$skill-installer` bundled skill (Python) copies from `openai/skills` or any GitHub path at a `ref` | none |
| Cursor | `.agents/skills`, `.cursor/skills`; legacy `.claude/skills`, `.codex/skills` | same under `~` | plugins via `.cursor-plugin/marketplace.json`; team marketplaces (Default Off/On/Required) | none |
| GitHub Copilot | `.github/skills`, `.claude/skills`, `.agents/skills` | `~/.copilot/skills`, `~/.agents/skills` | `gh skill` (preview): install, update, preview, search, publish, list | user-global `~/.agents/.skill-lock.json` (Vercel v3 format); `--pin` tag/sha |
| Gemini CLI | `.gemini/skills`, `.agents/skills` | `~/.gemini/skills`, `~/.agents/skills`, extensions | `gemini skills install <git-url / path / .skill zip>` | none (default branch, overwrite) |
| Kiro | `.kiro/skills` | `~/.kiro/skills` | "Import a skill" from GitHub URL or folder (copy) | none documented |
| OpenCode | `.opencode/skills`, `.claude/skills`, `.agents/skills` | `~/.config/opencode/skills`, `~/.claude/skills`, `~/.agents/skills` | none | none; `permission.skill` globs |

Sources:
- Codex: https://learn.chatgpt.com/docs/build-skills (308 target of
  developers.openai.com/codex/skills); invocation `$name` or `/skills`; installer at
  `openai/codex@970111f` `codex-rs/skills/src/assets/samples/skill-installer/{SKILL.md,scripts/install-skill-from-github.py}`.
  Plugin marketplaces record `ref`, `sparse_paths`, `last_revision` in per-user config.toml
  (`codex-rs/config/src/types.rs`); admin allowlist with optional exact `ref`
  (`codex-rs/core-plugins/src/marketplace_policy.rs`).
- Cursor: https://cursor.com/docs/context/skills, https://cursor.com/docs/plugins (plugins bundle
  rules, skills, agents, commands, MCP, hooks).
- Copilot: https://docs.github.com/en/copilot/concepts/agents/about-agent-skills.
- `gh skill`: `cli/cli@4f2cfe9`, release v2.103.2 (2026-10-23). `pkg/cmd/skills/{install,update,preview,search,publish,list}`;
  without a version it takes the latest release tag, else default-branch HEAD; `--pin`/`@VERSION`
  as tag or sha (`pkg/cmd/skills/install/install.go:140-141,243`); lock `lockVersion = 3`
  "must match Vercel's CURRENT_LOCK_VERSION for interop", stores GitHub tree sha as
  `skillFolderHash` and `pinnedRef` (`internal/skills/lockfile/lockfile.go`); rewrites `SKILL.md`
  frontmatter with `github-repo`, `github-ref`, `github-tree-sha`, `github-path`, `github-pinned`
  (`internal/skills/frontmatter/frontmatter.go`), so installed bytes differ from upstream; `update`
  compares tree shas, skips pinned, has `--dry-run`/`--force`/`--unpin`
  (`pkg/cmd/skills/update/update.go`). Telemetry on by default for skill commands
  (`pkg/cmd/skills/skills.go`), opt-out `GH_TELEMETRY=0` / `DO_NOT_TRACK=1`
  (`internal/telemetry/telemetry.go`).
- Gemini CLI: https://geminicli.com/docs/cli/skills/; `google-gemini/gemini-cli@cd1b45c`
  `packages/cli/src/utils/skillUtils.ts` (clone, `fs.cp`, overwrite; no ref, no hash); release
  v0.65.0 (2026-10-20).
- Kiro: https://kiro.dev/docs/skills/. OpenCode: https://opencode.ai/docs/skills/.

#### Verdict

Only `gh skill` records anything lock-like, and it is user-global: tree sha plus optional pinned
ref. No install-from-lock, no content-hash check, no frozen mode. Codex, Gemini, Kiro and Cursor
copy or index the current head.

#### Implications for the spec

- D5 (`.agents/skills` canonical) is confirmed: Codex, Cursor, Copilot, Gemini CLI, OpenCode read
  it. Claude Code (`.claude/skills`) and Kiro (`.kiro/skills`) still need links; Kiro symlink
  support unverified.
- Add `gh skill` to the alternatives: first-party, preinstalled for many users, pins a tag or sha,
  but user-global lock only, no project lock, no hash verification, no frozen mode, and it edits
  `SKILL.md`.
## 4a. APM (Agent Package Manager)

Repo moved: `danielmeppiel/apm` redirects to `microsoft/apm` (`gh repo view` 2026-10-26). Checked
`microsoft/apm@2920043` (2026-10-23); latest tag `v0.35.0` (2026-10-22), PyPI `apm-cli` 0.35.0
uploaded 2026-10-22. Python CLI (`pyproject.toml`), MIT, install via `install.sh`/`install.ps1`/pip.
Paths below are at `2920043`.

### (a) Facts

- **Scope**: manages more than skills: instructions, prompts, agents, skills, commands, hooks,
  MCP servers, LSP servers, Claude plugins; deploys to 14 targets incl. copilot, claude, cursor,
  codex, gemini, opencode, windsurf, kiro, antigravity, hermes, `agent-skills` (`.agents/`)
  (`docs/src/content/docs/reference/targets-matrix.md` "Summary"). Skills converge on
  `.agents/skills/` for most targets; Claude, Kiro, Grok keep native dirs (same file). Can also
  generate `AGENTS.md`/`CLAUDE.md` (`apm compile`).
- **Manifest** `apm.yml`: `dependencies.apm` (git `owner/repo[/path]#ref`, local paths,
  marketplace objects), `dependencies.mcp`, `targets`, `scripts`, `lifecycle`
  (`docs/.../reference/manifest-schema.md`, repo's own `apm.yml`). Plain skill repos are a package
  type (`claude_skill`, `docs/.../reference/lockfile-spec.md:278`).
- **Lock** `apm.lock.yaml` (`docs/.../reference/lockfile-spec.md`): per dependency `repo_url`,
  `resolved_commit` (40-hex), `resolved_ref`, `version`, `depth`, `resolved_by` (transitive
  parent), `package_type`, `deployed_files`, `deployed_file_hashes`, `content_hash`
  (sha256 of sorted paths + raw bytes, `:294`), `declared_license`; registry entries add
  `resolved_url` and `resolved_hash` ("verified on every install", `:292`). Also records MCP/LSP
  configs and a `deployments` ownership ledger.
- **Hash verification in code**: on download, a fresh `content_hash` differing from the lock raises
  `DirectDependencyError("Content hash mismatch ... may indicate a supply-chain attack. Use 'apm
  install --update' ...")` (`src/apm_cli/install/sources.py:855-885`). Cached copies are
  re-hashed and re-downloaded on mismatch (`src/apm_cli/install/phases/integrate.py:264-279`).
- **Frozen**: `apm install --frozen` requires the lock, replays pins, never rewrites, refuses
  declaration drift (`docs/.../reference/cli/install.md:49`). `apm audit --ci` re-installs into a
  scratch tree and reports drift of deployed files as text/JSON/SARIF
  (`docs/.../reference/cli/audit.md` "Description"). Transitive deps keep locked commits until
  `apm update` (`lockfile-spec.md` intro).
- **Semver**: git deps accept `#^1.2.0`, `#~1.4`, bounded ranges, resolved against remote tags
  (`docs/.../consumer/manage-dependencies.md:379-443`). `apm outdated`, `apm update --dry-run`
  (`docs/.../consumer/update-and-refresh.mdx:58,158`).
- **Dependencies**: transitive, from each package's `apm.yml` (`lockfile-spec.md` `depth`,
  `resolved_by`).
- **Registries**: HTTP registry protocol (`docs/.../reference/registry-http-api.md`), behind
  `apm experimental enable registries` (`docs/.../guides/registries.md`); `apm publish`, `apm pack`
  bundles, registry proxy and "registry-only" mode for enterprises
  (`docs/.../enterprise/registry-proxy.md`). Private git via GitHub/ADO auth
  (`docs/.../consumer/private-and-org-packages.md`).
- **Policy**: org `apm-policy.yml` discovered from the git remote; allow/deny lists,
  `require_pinned_constraint`, content-type allow lists, inheritance where children cannot relax
  (`docs/.../reference/policy-schema.md:111,176,295`).
- **Content scanning**: blocks hidden Unicode (tag chars U+E0001-E007F, bidi overrides,
  zero-width) before deploy; `apm audit --strip` cleans (`docs/.../enterprise/security.md:148-177`).
  "does not do malware analysis ... does not sign packages" (`security.md:12`).
- **Code execution**: packages can ship hooks, `bin/` executables, MCP/LSP servers and (experimental)
  canvas `extension.mjs`, which the harness then runs. An "executable trust gate" can block them
  but is **opt-in** (`security.md:453-470`). APM itself does not run package scripts; project
  `lifecycle:` scripts (shell or HTTP) run only after `apm lifecycle trust`
  (`docs/.../enterprise/lifecycle-scripts.md`). `apm run` runs `scripts:` from the manifest.
- **Telemetry**: none: "APM collects no usage data, analytics, or diagnostics" (`security.md`
  "What APM does NOT do"); grep of `src/` finds no telemetry client.
- **Cooldown**: none found (grep `cooldown|release_age|min_age` in `src/` and docs: no hits).

### (b) Lock/integrity verdict

Pins commit: **yes** (`resolved_commit`). Verifies hash: **yes**, fails install on mismatch for
fresh downloads; registry archives also checked by `resolved_hash`. Frozen/CI: **yes**
(`install --frozen`, `audit --ci` with SARIF). Semver: **yes** (git tags + registry).

### (c) What it has that skillcask lacks

- Transitive deps declared in the package manifest, plus non-skill primitives (instructions,
  hooks, MCP, LSP, plugins) and `AGENTS.md` compilation.
- Per-file `deployed_file_hashes` and an ownership ledger: drift of *deployed* files (hand edits)
  is detected by `apm audit`, not just source hashes.
- Org policy file with inheritance, SARIF output, hidden-Unicode scanner, executable trust gate.
- Bundles (`apm pack`/`unpack`) for air-gapped installs; registry proxy mode.

### (d) Corrections to the spec

The spec does not mention APM. It should: the Problem statement "No skill tool does all of it
for repositories in any language" is no longer true for commit pin + content hash + frozen
install + semver + no telemetry. APM lacks a release-age cooldown and lets packages ship
executables (hooks/MCP) unless the opt-in gate is on; skillcask's distinguishing points are now
data-only packages, cooldown, a single Rust binary (APM is Python, shipped as a standalone binary via `install.sh` and Homebrew core, `docs/.../getting-started/installation.md:16-21`),
and the Composer-repository distribution, not lockfile integrity itself.
## 4b. ClawHub (OpenClaw skills registry, `clawhub` CLI)

Checked `openclaw/clawhub@e726f3c` (2026-10-26). In-repo CLI `packages/clawhub/package.json`
0.24.0 (unreleased); npm `clawhub` latest 0.23.3 (modified 2026-08-04). Code MIT (`LICENSE`);
hosted service on Convex.

### (a) Facts

- **Registry**: skills published to clawhub.ai as `@owner/slug` with semver; `skill publish` and
  `sync` start at `1.0.0` and bump patch per change (`--bump minor|major`); identical content
  fingerprint is a no-op (`docs/cli.md` "skill publish", "sync"). All skills relicensed `MIT-0`
  (`docs/skill-format.md` "License"). Withdrawn versions keep their number
  (`packages/clawhub/src/cli.ts:447`).
- **Install**: `clawhub install @owner/slug` takes latest unless `--version` (exact, no ranges);
  zip from `/api/v1/download` extracted to `<workdir>/skills/<slug>` (`--dir`, default `skills`)
  (`docs/cli.md`). Writes `<workdir>/.clawhub/lock.json` and `<skill>/.clawhub/origin.json`.
- **Lock** (`packages/schema/src/schemas.ts:21-33`): `{version:"1", skills:{[slug]:{version|null,
  installedAt, ownerHandle?, sourceRef?, pinned?, pinReason?}}}`. **No hash.** `origin.json` adds a
  `fingerprint` (sha256 over sorted `path:sha256` lines, `packages/clawhub/src/skills.ts:14-32,141-147`).
- **Hash checks**: registry skill zips are **not** checked against any hash
  (`cmdInstall`, `packages/clawhub/src/cli/commands/skills.ts:416-620`). The fingerprint is used
  only by `update` to refuse overwriting locally modified skills without `--force`
  (`docs/cli.md` "update"). Exceptions: skills.sh skills proxied as `skills-sh:owner/repo/slug`
  are fetched as a GitHub zip at a resolved commit and fail if the folder hash differs from the
  one ClawHub's resolver approved (`skills.ts:1771-1782`); plugin packages are verified against
  SHA-256 and npm `sha512`/shasum (`docs/cli.md` "package download/verify").
- **Pin**: `clawhub pin <skill> [--reason]`; `update --all` skips, `install --force` refuses
  (`docs/cli.md` "pin"). No restore-from-lock command, no `--frozen` (grep of `cli.ts`).
- **Scanning (verified)**: each version gets ClawScan, skillspector, static analysis and
  **VirusTotal** reports; `scan download` returns them as a ZIP (`docs/cli.md:271-295`,
  `docs/http-api.md:452,501,1515,1537`). Statuses Pass/Review/Warn/Malicious/Pending/Error
  (`docs/security-audits.md`). Install refuses `moderation.isMalwareBlocked`; `isSuspicious` needs
  `--force` non-interactively (`skills.ts:539-557`, update at `:893-914`); malicious releases get
  HTTP 403 on download.
- **Publish**: GitHub login (`clawhub login`); GitHub Actions OIDC trusted publishing for plugin
  packages (`docs/publishing.md:252-269`); moderation, reports, namespace claims
  (`docs/moderation.md`, `docs/namespace-claims.md`).
- **Deps**: none between skills; frontmatter `metadata.openclaw.requires.{env,bins,anyBins,config}`
  and `install` specs (`brew`, `node`, `go`, `uv`) (`docs/skill-format.md:75-121`). OpenClaw's
  macOS Skills UI runs install specs only when the user starts them
  (https://docs.openclaw.ai/tools/skills).
- **Targets**: one dir, `<workdir>/skills`. OpenClaw reads `<workspace>/skills`, then
  `<workspace>/.agents/skills`, `~/.agents/skills`, managed dir (docs.openclaw.ai/tools/skills).
  No per-agent linking.
- **Private registry**: `--registry` / `CLAWHUB_REGISTRY` and registry discovery
  (`docs/cli.md:28-40,133`); server is open source but needs Convex.
- **Telemetry**: install events only when logged in (slug, version, owner, source repo/path, scan
  status), opt-out `CLAWHUB_DISABLE_TELEMETRY=1` (`docs/telemetry.md`); feeds `installsAllTime` /
  `installsCurrent`.
- **Code execution**: CLI runs no package code; only child process is `curl` for the HTTP fallback
  (`packages/clawhub/src/http.ts:776`).

### (b) Lock/integrity verdict

Pins exact registry version (commit only for skills.sh-proxied skills); lock has no content
hash; native skill zips not verified; no frozen mode, no restore from lock.

### (c) What it has that skillcask lacks

Hosted search with install counts; per-version multi-engine scanning (VirusTotal + LLM/static)
with download blocking and a suspicious-content gate; `pin --reason`; `inspect --file` before
install; OIDC trusted publishing; moderation and reports.

### (d) Spec corrections

Not mentioned in the spec. Suggested bullet: "ClawHub: semver registry with VirusTotal/LLM
scanning, but its lock has no hash, registry zips are not verified, and there is no restore or
frozen install."

## 5. Other tools

**numman-ali/openskills** (npm 1.5.0, 2026-01-17; repo `57d933a`, 2026-01-18, inactive since).
`git clone --depth 1` of the default branch (`src/commands/install.ts:157`, `update.ts:97`);
per-skill `.openskills.json` with `source`, `sourceType`, `repoUrl`, `subpath`, `installedAt`, no
ref/commit/hash (`src/utils/skill-metadata.ts`). No lock, frozen mode, semver or telemetry.
Installs to `.claude/skills` or `.agent/skills` (singular, `src/utils/dirs.ts:8-23`) and writes an
`<available_skills>` XML index into `AGENTS.md`. Runs no package code, but interpolates `repoUrl`
into an `execSync` shell string. Verdict: no pin, no verification.

**rulesync** (`dyoshikawa/rulesync`; npm 41.0.0, 2026-10-24; repo `d2fdee0`, 2026-10-26; MIT).
**Strongest lock of this group and not in the spec.** `rulesync.jsonc` declares `sources` (GitHub,
git, npm); `rulesync.lock` records `requestedRef`, resolved commit (`resolvedRef`) and per-skill/rule
sha256 `integrity` (`docs/guide/declarative-sources.md:133,254-280`). Cached content is re-checked
and restored at the locked ref; a mismatch at the locked commit "warns and takes it" normally and
refuses under `install --frozen` (`declarative-sources.md:256`; `src/lib/sources.ts:1828,1874`).
Checks that a locked commit is still in the ref's history (catches force-push, `:216`).
`install --outdated` is a read-only drift check with exit codes 0/1/2 (`:282-300`). npm transport
(experimental) checks `dist.integrity`, exact version or dist-tag only (`:105-127`). Modes
`--mode apm` (reads `apm.yml`) and `--mode gh` (mirrors `gh skill`). Generates rules, skills,
hooks, MCP, permissions for many agents. No git semver, no cooldown, no skill deps; no telemetry
code found (grep). Runs no package code (writes agent hook configs; refuses executed-command keys
from fetched permissions, `docs/reference/file-formats.md`).

**skillkit** (`rohitg00/skillkit`; npm 1.24.0, 2026-04-21; repo `d2e5c34`, 2026-06-02). Global lock
`~/.skillkit/lock.json` (`packages/core/src/config.ts:170`) with `source`, `sourceType`,
`installedAt`, `checksum`, `agents`, `path`, no ref/commit
(`packages/cli/src/commands/install.ts:635-642`); checksum only skips unchanged skills on
`update` (`update.ts:153`). `.skills` manifest without version pins. Local `SkillScanner` on by
default (`install.ts:133,422`). 40+ agents, plus translate/run/mesh/memory/marketplace features.
No frozen mode, no semver, no telemetry code found (grep). Verdict: no pin, no verification.

**netresearch/composer-agent-skill-plugin** (release v2.1.1, 2026-06-09; `master` `20d15d6`,
2026-10-19, unreleased changes). Spec statements still hold but understate it:
- Packagist `type=ai-agent-skill` still **57** (`https://packagist.org/search.json?type=ai-agent-skill`,
  2026-10-26).
- Direct sources (`extra.ai-agent-skills`) lock into `composer.skills.lock` with a 40-hex commit
  and a checksum; install throws "Checksum mismatch" (`src/DirectSkills/DirectSkillsCoordinator.php:164-191`)
  and fails on a stale lock (`:78`).
- Since 2.1.0: semver over git tags (`owner/repo:^1.2` via `composer/semver` + `git ls-remote
  --tags`), `skills:outdated` drift report, symlink rejection; since 2.0.0 a deny-by-default trust
  map (`skills:trust`, `allow-skills`) (`CHANGELOG.md`).
- Still no agent-dir linking: copies to `vendor/agent-skills/installed/` and indexes in
  `AGENTS.md` (README).
- Needs PHP + Composer; the plugin is code, skill packages are data.
## Summary table

"partial" = only for some sources or only outside the default path. Cell basis is in the section
for each tool. skillcask row from `docs/specs/2026-10-19-skillcask-v1.md` (D6, D7, D10, D16, D27).

| tool (version checked) | pins commit | verifies hash | frozen CI | semver | private registry | cooldown | deps | diff review | telemetry | runs code |
|---|---|---|---|---|---|---|---|---|---|---|
| skillcask (spec) | yes | yes | yes (`install --frozen`) | yes | yes (Composer repos) | yes (D7, D15, D28) | yes (D16) | yes (`diff`, D27) | none | no |
| vercel-labs/skills 1.7.4 | no (manual sha as ref only) | no (hash only skips unchanged in `update`) | no (`check` = `update`, mutates) | no | no (private git only) | no | partial (npm `package.json` `skills` field) | no | on by default; `DISABLE_TELEMETRY`/`DO_NOT_TRACK` | no |
| Tessl CLI 0.118.0 | yes (GitHub sha in `tessl.json`) | no | no (vendored mode instead) | yes (compatible updates; ranges unverified) | yes (SaaS workspaces, SSO) | yes (org release/commit age, 0.82.0) | no | no (`outdated` list only) | on by default, may include file contents | yes (hooks, MCP) |
| Claude Code plugins | author-side `sha` only; no consumer lock | partial (`archive` + `sha256`) | no | partial (plugin deps via tags; `version` not semver) | yes (private git, archive auth, managed allowlist) | no | yes (plugin `dependencies`) | no (component inventory only) | OTel opt-in; Anthropic analytics | yes (hooks, MCP/LSP, monitors, `bin/`) |
| `gh skill` (gh 2.103.2, preview) | optional (`--pin`) | no | no | no (latest tag else HEAD) | GitHub auth only | no | no | `preview` (content, not diff) | on by default; `GH_TELEMETRY=0` | no |
| Codex / Gemini CLI / Kiro / OpenCode / Cursor native | no | no | no | no | via git creds / Cursor team marketplaces | no | no | no | not checked | Cursor/Codex plugins can carry hooks, MCP |
| APM (microsoft/apm 0.35.0) | yes (`resolved_commit`) | yes (fails on mismatch) | yes (`install --frozen`, `audit --ci` SARIF) | yes (git tags, registry) | yes (experimental HTTP registry, proxy) | no | yes (transitive) | partial (`outdated`, `update --dry-run`; no content diff) | none | packages can ship hooks/MCP/`bin/`; opt-in trust gate |
| ClawHub 0.23.3 / 0.24.0 | no (exact registry version; commit for skills.sh proxy) | partial (skills.sh proxy, plugin artifacts) | no | yes (exact version on install) | yes (`--registry`, self-host on Convex) | no | no | no (`inspect --file`, scan reports) | when logged in; `CLAWHUB_DISABLE_TELEMETRY=1` | no |
| openskills 1.5.0 | no | no | no | no | git creds | no | no | no | none found | no |
| rulesync 41.0.0 | yes (`resolvedRef`) | yes under `--frozen`, warns otherwise | yes (`--frozen`, `--outdated`) | no | git creds; npm `registry` + token | no | no | no | none found (grep) | no |
| skillkit 1.24.0 | no | no | no | no | git creds | no | no | no | none found (grep) | no (local scanner) |
| composer-agent-skill-plugin 2.1.1 | yes (direct sources) | yes | yes (lock applied, stale lock fails) | yes | yes (any Composer repo) | no | yes (Composer `require`) | no (`skills:outdated`) | none found | plugin is PHP; skills are data |

## Bottom line for the spec

1. The vercel-labs/skills critique is still correct at `v1.7.4` (`a80e4c9`); update the version and
   commit, add that `skills check` now mutates (`src/cli.ts:420`), and drop D11's "needs a Vercel
   OIDC token" (the skills.sh search and download APIs answered anonymously on 2026-10-26).
2. "No skill tool does all of it" (Problem section) is no longer accurate. APM (commit pin,
   content-hash failure, frozen install, semver, transitive deps, no telemetry) and rulesync
   (commit pin, per-skill integrity, `--frozen`, `--outdated`) both do the lock part, and the
   composer plugin now verifies checksums and supports semver. Tessl has a release-age cooldown.
   What none of them combine: content-hash lock + frozen install + release-age cooldown + text diff
   of updates + data-only packages + one static binary with no runtime. Reword the claim to that.
3. Add APM, rulesync, Tessl, ClawHub and `gh skill` to the alternatives list. `gh skill` matters
   because it ships with the GitHub CLI and writes a Vercel-compatible user lock.
4. Things worth considering from competitors (not proposals, just gaps): deployed-file drift
   audit with SARIF (APM), org policy file with inheritance (APM, Tessl, Claude managed settings),
   force-push detection on locked commits (rulesync), third-party scan results at install time
   (skills.sh, ClawHub), `.well-known` HTTP discovery (agentskills.io schema, used by
   vercel-labs/skills).
