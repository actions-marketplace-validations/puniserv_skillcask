# Landscape: agent-skill package managers (2026-10-26)

Scope: every tool found in 2025–2026 that installs or manages Agent Skills (`SKILL.md` dirs) or close
equivalents (agent plugins/extensions). Compared against skillcask 0.6.0 (`puniserv/skillcask@961f568`).

Method: GitHub search (topics `agent-skills`, `skills-cli`, keyword searches), npm/crates.io/PyPI/Homebrew
APIs, web search (EN/CN/JA) for discovery only. Every claim below checked at a primary source: shallow clone
at the listed commit + grep/read of code, or official docs/changelog when closed source. Stars from `gh api`
on 2026-10-26. "not found" = looked, absent. "docs-only" = docs claim it, code not verified (closed or not
traced). Citation shorthand `o/r@sha path:L` = `https://github.com/o/r/blob/<sha>/path#L<L>`.

## 1. Verdict (Q1)

No existing tool is a drop-in for skillcask, but two come close enough that "nobody does this" is no longer
true for most individual features. **microsoft/apm** (Python, 4.1k★, v0.35.0) has a lock with resolved commit +
sha256 content hash verified on install, `install --frozen`, semver ranges on git tags, an org policy file
(`apm-policy.yml`, allow/deny sources), hidden-Unicode scanning that blocks install, git-credential-helper auth,
and Renovate + (merged) Dependabot support; it lacks a release-age cooldown, Composer sources and a prompt-text
diff, and it deploys hooks/MCP (gated by `apm approve`). **Goldziher/ai-rulez** (Go single binary, 163★,
v5.7.0 released today) has a digest lock with `--locked/--frozen`, npm-style ranges on tags,
`min_release_age` with an org policy that enforces a floor (the same idea as skillcask D-cooldown), `allowed_hosts`
policy, hidden-character lint, credential-helper auth, Sigstore-signed lock, SBOMs and reviewer approvals; it is
a rules/config generator that also installs skills and hooks, not a skills package manager, and has no
Composer sources or text diff. The mass-market tools (vercel `npx skills` 36.6k★, `gh skill`, Claude Code /
Codex / Gemini plugin systems) do **not** verify content hashes on install, have no project lockfile that
pins+verifies, no frozen mode, no cooldown. What remains distinctive to skillcask: **Composer repositories
(Packagist, GitLab Composer registry, Satis) as a source from a language-neutral binary, `publish` to a static
Composer repo, a review diff of SKILL.md text before an update is applied, and the specific combination** (hash
lock + frozen + ranges + cooldown + enforced source policy + no code execution + no telemetry) in one binary.
Sensible alternatives today: APM if you accept Python, a broader scope and hooks; ai-rulez if you want rule
generation too; vercel `skills` if you need reach and discovery and do not need integrity.

## 2. Inventory

### 2a. Main table (tools checked in depth)

Abbrev: GH=GitHub, git=any git URL, reg=own registry, loc=local path, cred=git credential helper,
ranges=semver range constraints, "-"=no, nf=not found, d/o=docs-only.

| Tool | Repo | Lang | ★ | Last release | Sources | Manifest | Lock (pins) | Hash verify on install | Ranges | Frozen / CI gate | Private / auth | Agents | Cooldown | Skill deps | Update diff | Telemetry | Runs pkg code | Win | Global | Publish side |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **skillcask** (ref) | puniserv/skillcask | Rust | 0 | 0.6.0 | Composer repos (Packagist, GitLab, Satis, static), GH | skills.toml | skills.lock: version, archive sha256, tree hash | yes | Composer semver | `install --frozen`, `outdated --strict` | cred/keychain | .agents/skills store + links (.claude, .kiro, …) | `min-release-age`, org-enforced | `requires:` frontmatter | `diff`, `update --diff` | none | never | yes | `--global` | `publish` → static Composer repo |
| vercel `skills` (`npx skills`, ex-`add-skill`) | vercel-labs/skills | TS | 36,609 | v1.7.4 2026-10-19 | GH, GitLab, Azure Repos, git, loc, URL/zip, `/.well-known`, npm (exp.) | none (`package.json` `skills`, exp.) | `skills-lock.json`: source, user ref (not resolved commit), `computedHash` sha256 | **no** (hash only for update detection) | - | - (`experimental_install` restores by ref) | cred → `gh` → SSH; GH token | ~80 (.agents/skills + symlinks or `--copy`) | - | - | - (hash compare only) | **on**; `DISABLE_TELEMETRY`/`DO_NOT_TRACK` | no hooks (`use` launches agent) | yes (junctions) | `-g` | skills.sh catalog, leaderboard, partner audits |
| `gh skill` | cli/cli | Go | 46.7k | v2.103.2 2026-10-23 | GH (any host), loc | none (provenance in SKILL.md `metadata`) | `~/.agents/.skill-lock.json` v3 (Vercel-compatible, user-global): ref, git tree SHA | **no** (blobs by SHA via API, no re-hash) | - (`@tag`/`--pin`) | - (`update --dry-run` exit code) | gh keyring token | 48 IDs, copies | - | - | - | **on**; `GH_TELEMETRY`/`DO_NOT_TRACK` | no (warns) | yes | `--scope user` | `gh skill publish` (validate, tag, release) |
| Claude Code plugins | anthropics/claude-code (closed) | TS | 153k | v2.1.310 | marketplace: GH/git/url/file/dir; plugin: GH/git-subdir/url/npm/archive/command | marketplace.json + plugin.json; enable in .claude/settings.json | no project lock; user `installed_plugins.json` (version+commit) | archive `sha256` opt-in; npm integrity; git = sha checkout | plugin deps only (npm semver vs `<name>--v<ver>` tags) | - (seed dir for CI) | non-interactive cred helper / ssh-agent; `headersHelper` | Claude only | - | plugin deps | - | org OTel/analytics | **yes** (hooks, MCP, LSP, `command` source) | yes | user/project/managed | git marketplace; `plugin tag` |
| Codex skills + plugins | openai/codex | Rust | 131k | rust-v0.164.0 2026-10-23 | `$skill-installer`: GH; plugins: loc/git(ref,sha)/npm | `.agents/plugins/marketplace.json` or `.claude-plugin/marketplace.json` | none | nf | - | - | git creds, GH token | Codex only | - | d/o | - | plugin metrics module | plugins: hooks+MCP; installer = agent-run Python | yes | `~/.agents/skills`, `/etc/codex/skills` | git marketplace |
| Gemini CLI ext/skills | google-gemini/gemini-cli | TS | 108k | v0.65.0 2026-10-20 | git, GH release, loc | gemini-extension.json | none | nf | - | - | git | Gemini (reads .agents/skills) | - | - | consent re-prompt, no diff | not checked | **yes** (hooks, MCP) | yes | user/workspace | GH releases |
| Cursor / Kiro / OpenCode / Amp | closed | – | – | – | marketplaces / GH import / HTTP catalog / `amp skill add` | plugin.json, POWER.md, opencode.json | none documented | none documented | - | - | d/o | self only | - | - | - | – | plugins: hooks/MCP | d/o | yes | marketplaces |
| **APM** | microsoft/apm (ex danielmeppiel/apm) | Python | 4,127 | v0.35.0 2026-10-22 | GH/GHES, GitLab, Azure DevOps, git, loc, marketplaces, REST reg (exp.) | apm.yml | apm.lock.yaml: commit, tag, constraint, `content_hash`, per-file hashes, license | **yes** | yes (git tags) | `install --frozen`, `audit --ci` (SARIF) | per-org PAT, `gh auth token`, cred, `az` | 14 targets | - | yes (transitive apm.yml) | - (ref plan only) | none found | hooks/bin/MCP after `apm approve`; lifecycle scripts after `lifecycle trust` | yes | `-g` | `publish` (exp.), `pack`, marketplace |
| Tessl | tesslio/cli (proprietary binary) | closed | 70 | @tessl/cli 0.118.0 2026-10-23 | Tessl reg, GH, git, file | tessl.json (exact versions) | nf in docs ("vendored" mode commits files) | nf | implied (`outdated`) | nf | workspaces, API keys, git creds | 11 | nf | plugins bundle skills | nf | **on**, `shareUsageData` opt-out | nf | yes | `--global` | hosted reg, evals, Snyk scores |
| ClawHub CLI | openclaw/clawhub | TS | 9,528 | v0.23.3 2026-08-04 | ClawHub reg, skills.sh, GH | none | `.clawhub/lock.json`: version, scan status, pin (no hash) | no for skills (plugins: sha256) | - | - (`pin`) | token/device login | OpenClaw | nf | - | - | **on** when logged in, opt-out | nf | n/v | n/v | `publish` (auto patch bump), VirusTotal, stars/downloads |
| tech-leads-club agent-skills | tech-leads-club/agent-skills | TS | 7,089 | CLI 1.6.0 2026-10-14 | single curated catalog (npm via jsDelivr) | none | `.agents/.skill-lock.json`: contentHash, version | **yes** (catalog hash) | - | - | - | ~40 | - | - | - | nf | no | n/v | `-g` | curated catalog, Snyk scan in CI |
| iflytek SkillHub | iflytek/skillhub | Java + TS CLI | 5,297 | cli-v0.2.0 2026-10-26 | self-hosted reg (ClawHub-compatible API) | none | none (per-skill metadata.json w/ fingerprint) | **yes** | nf (exact + tags) | - | OAuth device, scoped tokens, RBAC | codex, claude, pi, … | - | - | `sync` local vs remote | nf | no | yes | `--scope user` | self-hosted reg, review workflow, audit log, Cisco scanner |
| **ai-rulez** | Goldziher/ai-rulez | Go (+npm/PyPI/brew wrappers) | 163 | v5.7.0 2026-10-26 | git https/ssh, GH shorthand, loc | `.ai-rulez/config.toml` | ai-rulez.lock: commit + sha256 tree digest per skill/item/output | **yes** | yes (npm-style on tags) | `--locked/--frozen`, `lock --check/--diff/--outdated` | cred helper, `AI_RULEZ_GIT_TOKEN` | 52 harnesses (generates native files) | **yes** `min_release_age`, org floor | nf | - (`approve --diff` = file list+scan, not text) | opt-in, local | can install hooks | n/v | user config | GH releases, npm, OCI |
| rulesync | dyoshikawa/rulesync | TS (+Bun binaries) | 1,552 | v41.0.0 2026-10-24 | GH API, git (ADO, Bitbucket, file://), npm-compatible regs (exp.) | rulesync.jsonc | rulesync.lock: requested ref, commit, sha256 per skill; npm lock w/ integrity | **yes** (warn; hard fail under `--frozen`) | - (explicitly out of scope) | `install --frozen`, `--outdated` exit 0/1/2 | `--token`, npm tokenEnv to trusted hosts | ~60 (generates native files) | nf | nf | - | none found | no | yes (CI) | `--global` | generates plugin dirs |
| composer-agent-skill-plugin | netresearch/composer-agent-skill-plugin | PHP | 11 | v2.1.1 2026-06-09 | Composer pkgs (any Composer repo); direct GH, loc | composer.json | composer.lock + `composer.skills.lock` (commit, sha256 tree) | yes (direct sources); packages: Composer's | **yes** (composer/semver) | stale-lock error; `skills:outdated --strict` | Composer auth | none (AGENTS.md XML index; skills stay in vendor/) | nf | Composer `require` | - | nf | **is** a Composer plugin (executes) | n/v | - | Packagist via git tag |
| qvr (quiver) | try-agora/qvr | Go | 25 | v0.30.0 2026-06-30 | git | qvr.toml | qvr.lock: commit, subtreeHash, scan verdict, author | **yes** (drift = error) | - (latest semver tag only) | `sync --locked/--frozen/--check` | cred helper (osxkeychain hint) | ~60 | nf | nf | - (`diff` = local edits) | none | no | yes | `--global` | `publish` = git tag |
| skillpm (Go) | comountainclimber/skillpm | Go | 0 | v0.1.1 2026-08-19 | GH, loc | none (lock only) | skills.lock: commit, sha256 tree, scanDigest | **yes, always** | - | `ci --frozen`, GH Action | git | claude, cursor, codex, agents | nf | - | - | none | no | n/v | - | - |
| skillpm (npm) | sbroenne/skillpm | TS | 14 | v2.0.0 2026-09-28 | npm | package.json | npm package-lock | npm SRI | npm | `npm ci` | npm auth | via `skills@1.7.0` | npm-level only | npm deps | - | inherits vercel | **yes** (npm lifecycle scripts) | yes | - | npm publish |
| skills-lock | luisalima/skills-lock | JS | 1 | 0.1.0 2026-06-12 | GH, git, file | package.json `skills` | skills-lock.json: commit, sha256 tree | only with `--frozen` | - | `install --frozen` | git | 7 + custom | nf | nf | - | none | no (empty hook template) | n/v | - | - |
| nodus | nodus-rs/nodus | Rust | 7 | v0.17.0 2026-06-02 | GH, git, loc | nodus.toml | nodus.lock: rev, digest, install_digest | via `--locked/--frozen` lock regen compare | **yes** (git tags) | `sync --locked/--frozen` | git | codex, claude, cursor, copilot, opencode, agents | nf | **yes** (transitive) | - (`review` = LLM review) | update check only | wires package hooks/MCP | yes | `--global` | generates Claude/Codex marketplaces |
| craft | erdemtuna/craft | Go | 1 | v0.5.0 2026-03-27 | GH tag/commit | craft.yaml | craft.pin.yaml: commit, sha256 | **yes** | - | nf | git | n/c | - | **yes** (transitive) | - | n/c | no | yes | n/c | vendors to `forge/` |
| grimoire | jeffreytse/grimoire | Go | 33 | v0.2.0 2026-07-19 | git | grimoire.toml | grimoire.lock: version, commit, sha256 of SKILL.md only | **no** (never compared) | yes | nf | git | 8 | nf | yes | - | nf | no | yes | n/v | git |
| rosie | rosieskills/rosie | Rust (+npm/wasm) | 157 | v0.8.5 2026-06-29 | GH, npm | none | `.agents/rosie.lock`: ref, sha, pin (no content hash) | - | latest tag only | - | GH_TOKEN, `gh auth token` | auto-detect | - | - | **unified diff in audit log (after update)** | nf | no; strips invisible Unicode | d/o | n/v | - |
| pspm | anyt-io/pspm-cli | TS | 6 | npm 0.15.1 2026-05-28 | own reg, GH, well-known, loc | pspm.json | lockfile: version, URL, sha256, commit | yes but skip-on-mismatch; fail only with `--frozen-lockfile` | yes | `--frozen-lockfile` | API key | 30+ | - | yes | - | nf | no | n/v | `-g` | pspm.dev |
| SPM (skillpkg) | skillpkg/spm | Go + CF registry | 0 | v1.2.3 2026-04-11 | skillpkg.dev | skills.json | skills-lock.json: version, URL, sha256 | **no** (written, never compared) | yes (server) | - | `spm login` | 30+ | - (24h publisher cooldown only in a plan doc) | n/v | - | nf | no | yes | n/v | publish + **Sigstore sign**, `spm verify` |
| skpm (skpm-sh) | skpm-sh/cli | TS (vercel fork) | 1 | npm skpm-cli 1.5.1 2026-03-30 | GH, GitLab, git, loc | none | skills-lock.json: computedHash (no commit) | - | - | - | git | 44 | - | **yes** (`dependsOn`) | - | **on** (skpm.sh/t) | **yes** (`postInstall`, `--trust-scripts`) | inherits | `-g` | - |
| skpm (domehahn) | domehahn/skpm | Go | 2 | v2.3.0 2026-06-08 | SkillForge reg, Artifactory | agent-skills.yaml | agent-skills.lock sha256 | yes (digest check) | yes | `--frozen-lockfile`, `skpm ci` | registry | multi | nf | n/c | - | n/c | n/c | n/c | n/c | registry + attestation pkg |
| kasetto | pivoshenko/kasetto | Rust | 212 | v3.11.0 2026-10-15 | n/c | kasetto.yaml | kasetto.lock: hash per asset | `--locked/--frozen` | n/c | yes | n/c | many | nf | n/c | - | n/c | n/c | n/c | n/c | - |
| skillmod | huija/skillmod | Go | 2 | v0.0.6 2026-09-29 | git | SKILL.mod | SKILL.lock: Go dirhash `h1:` | `verify` (CI gate) | pseudo-versions | yes (verify) | git | multi (`share` links) | nf | n/c | - | n/c | n/c | n/c | n/c | - |
| skillshare | runkids/skillshare | Go | 2,838 | v0.26.4 2026-10-24 | git | n/c | skills.lock.json: commit, tree_hash | `doctor` integrity | few | n/c | n/c | many (+MCP, hooks) | nf | n/c | - | n/c | n/c | yes (junctions) | n/c | GH Action `setup-skillshare` |
| skillfold | byronxlg/skillfold | TS | 15 | npm 2.9.0 2026-10-23 | loc, GH, npm | skillfold.yaml | skillfold.lock: commit/version + sha256 | **yes** | nf | `install --frozen`, `check` | n/c | Claude, Codex, Cursor | nf | nf | - | n/c | n/c | n/c | n/c | - |
| pixi-skills | pavelzw/pixi-skills | Python | 44 | v0.1.6 2026-09-25 | conda channels | pixi.toml | pixi.lock sha256 per pkg | via pixi | via conda | pixi `--locked/--frozen` | channel auth | 15 backends | **via pixi `exclude-newer`** | conda deps | - | nf | conda post-link n/c | n/v | pixi global | conda channel |
| agent-skills-cli | Karanjot786/agent-skills-cli | TS | 194 | v1.2.0 2026-10-11 | agentskills.in, GH, git, npm, loc | .skillsrc | `~/.skills/skills.lock` (user home): commit, sha256 of SKILL.md | **no** (`frozen` never compares) | - | `frozen` (no hash check), `audit --fail-on` | token, env, SSH, cred, netrc | 45 | - | - | `diff` of two skills, not on update | **on**, off in CI | `exec` runs skill scripts on request; installs MCP | yes | `-g` | marketplace |
| openskills | numman-ali/openskills | TS | 10,810 | v1.5.0 2026-01-17 | GH, git, loc | none | - | - | - | - | SSH/git | .claude/.agent + AGENTS.md index | - | - | - | none | no | n/v | `--global` | - |
| skills-npm | antfu/skills-npm | TS | 572 | v4.1.0 2026-10-15 | npm pkgs | package.json `skills` | skills-npm-lock.json (no hash) | via npm | via npm | - | npm | via vercel | - | packs | - | nf | `prepare` script | n/v | n/v | npm (merging into `skills experimental_sync`) |
| `skill` (Rust port) | qntx/skill | Rust | 6 | v0.8.3 2026-04-22 | = vercel | none | skills-lock.json computed_hash | - | - | - | git | = vercel | - | - | - | **on** (add-skill.vercel.sh/t) | nf | yes | yes | - |
| skillman | pi0/skillman | TS | 189 | v0.0.6 2026-01-31 | via `npx skills` | skills.json (no ref/hash) | none | - | - | - | delegated | delegated | - | - | - | inherits vercel | delegated | delegated | `--global` | - |
| skillkit (rohitg00) | rohitg00/skillkit | TS | 1,562 | v1.24.0 2026-04-21 | GH, GitLab, loc, gist, taps, marketplace | `.skills` | none | - | - | - | nf | 46 (+`translate`) | - | - | - | toggle, no sender found | no | n/v | yes | marketplace submit |
| asm | luongnv89/asm | TS | 959 | v2.24.0 2026-10-20 | GH, asm-registry, loc | none | global lock: commit, ref | - | - | - (`outdated`) | git ssh | many | - | leases (not deps) | - | none found | no | n/v | global | PR to asm-registry |
| skillfish | knoxgraeme/skillfish | TS (AGPL) | 330 | npm 1.0.39 2026-08-06 | GH | skillfish.json | none | - | - | `--dry-run` | nf | many | - | - | - | **on**, `DO_NOT_TRACK` | no | n/v | `--global` | skill.fish catalog |
| rolecraft | rolecraft-sh/rolecraft | JS | 96 | v2.6.2 2026-10-14 | loc, GH, GitLab, SSH, npm | profiles | .skill-lock.json v3 + content hash | `verify` cmd only; "no `--frozen`" (own README) | nf | `ci` re-resolves + compares | git/ssh | 90 (d/o) | - | - | `diff` two skills, `rollback` | none (FAQ) | scan; installs MCP | n/v | yes | - |
| bapm | Sdju/bapm | TS | 7 | no release | n/c | bapm.yml | bapm.lock.yaml | n/c | yes | `--frozen`, auto in CI | exp. registry | multi | - | n/c | - | n/c | n/c | n/c | n/c | CycloneDX export |
| skillctl (OCI) | vrothberg/skillctl | Go | 2 | no release | OCI registries | skillctl.yaml (digests) | digest in manifest | via OCI (n/c) | n/a | n/c | registry auth | n/c | - | - | - | n/c | n/c | n/c | n/c | OCI push; Renovate/Dependabot via OCI refs |
| skillfile | eljulians/skillfile | Rust | 175 | v1.9.2 2026-08-31 | GH, GitLab, loc, URL | Skillfile | Skillfile.lock: SHA/ref | n/c | n/c | n/c | n/c | many + custom | - | n/c | - | n/c | n/c | n/c | n/c | - |
| obra/superpowers | obra/superpowers | Shell/JS | 305k | v7.0.1 2026-10-21 | host marketplaces | 9+ host manifests | n/a | n/a | n/a | n/a | n/a | via hosts | n/a | n/a | n/a | n/a | **yes** (SessionStart hook) | `run-hook.cmd` | n/a | official marketplaces |

### 2b. Long tail (installers/managers, light check)

Light check only. "vlock" = reads/writes Vercel `skills-lock.json`/`.skill-lock.json` (grep, not traced).
None of these verify hashes on install where checked.

| Tool | Repo @sha | Lang | ★ | Last push/release | Lock | Notable |
|---|---|---|---|---|---|---|
| skills-manager (desktop) | xingkongliang/skills-manager @7a22192 | Rust/Tauri | 6,877 | v1.43.0 2026-10-21 | none found | GUI sync, 50+ tools |
| cc-switch | farion1231/cc-switch @42ef634 | Rust | 148,825 | v4.0.20 2026-10-24 | vlock | provider switcher; skill sync side feature |
| Skills-Manager | jiweiyeah/Skills-Manager @bc3c8bd | TS | 1,039 | v2.2.0 2026-08-25 | - | GUI, 32 tools |
| HarnessKit | RealZST/HarnessKit @bd1cc05 | Rust | 473 | v1.15.0 2026-10-24 | vlock | skills+MCP+hooks+plugins GUI |
| skills-manager (mac) | yibie/skills-manager @505d1ff | Swift | 459 | 2026-08-05 | vlock | native mac |
| skillport | gotalab/skillport @21ab194 | Python | 418 | v1.1.2 2026-06-24 | n/c | PyPI, MCP search |
| mcptoon | activeing123/mcptoon @10b9c0d | Python | 393 | 2026-10-26 | n/c | MCP+skills, Chocolatey |
| dsh-skills-manager | MichengAI/dsh-skills-manager @5d1e64c | JS | 349 | 2026-10-26 | - | DeepSeek Harness plugin |
| kitter | what1f/kitter @cf52c5e | Rust | 306 | v0.2.2 2026-10-22 | none | library + symlinks/junctions, AGENTS.md blocks |
| advai-cli | advai-x/advai-cli @b6ecbce | Python | 263 | 2026-09-09 | - | Homebrew |
| skills-link | shanliuling/skills-link @26487ae | TS | 197 | 2026-05-14 | - | 41+ agents |
| skills-manager | Rito-w/skills-manager @aa155f6 | Vue | 196 | 2026-07-04 | - | marketplace GUI |
| skills-manager | shenysun/skills-manager @55a84b2 | TS | 179 | 2026-10-26 | vlock | manage in chat, 70+ agents |
| SkillsManager | tddworks/SkillsManager @36615df | Swift | 170 | 2026-05-28 | - | mac browse/install |
| universal-skills-manager | jacob-bd/universal-skills-manager @14c268b | Python | 112 | 2026-09-07 | skills.lock.json (n/c) | - |
| AgentSkillsManager | lasoons/AgentSkillsManager @f603f68 | TS | 90 | 2026-01-17 | - | IDE extension |
| reorx/skm | reorx/skm @d4b90eb | Python | 78 | no release | skills-lock.yaml (HEAD after pull, not a pin) | symlink/hardlink/reflink |
| skills-manager | cchao123 @f5ab5fb, zunalabs @34b3da4, qCanoe @eb1db76, umutbozdag @2c963c1 | TS/HTML | 43–72 | 2026 | - | desktop/tray/dashboard |
| skillkit (robotbird) | robotbird/skillkit @89809ac | TS | 67 | 2026-08-23 | vlock | - |
| big-config | bigconfig-ai/big-config @2f27257 | TS | 57 | 2026-06-04 | - | "agentic package manager" |
| skilluse | skilluse/skilluse @a6fb923 | TS | 55 | v0.10.0 2026-01-12 | - | GH repos as registries |
| mTarsier | mcp360/mTarsier @8f14301 | TS | 50 | 2026-04-20 | - | MCP+skills GUI |
| skiller | beautyfree/skiller @019d1ab | TS | 48 | 2026-10-23 | - | - |
| skillsgist | Qsnh/skillsgist @023e084 | TS (Cloudflare) | 46 | v2.1.0 2026-10-21 | nf | self-hosted private registry |
| aweskill | Wehuman01/aweskill @89d7bbb | TS | 36 | v0.4.8 2026-09-13 | - | store + projections, `find` |
| skillcrew | yoanbernabeu/skillcrew @156873a | Go | 34 | v0.3.0 2026-10-12 | internal sha256 state | team governance (required/blocked), `propose` PR |
| skill-deck | Hccake/skill-deck @2c920e3 | Rust | 33 | 2026-10-26 | vlock | GUI ("cooldown" hits = API throttling) |
| flint | lcy362/flint @41c7e7a | TS | 33 | 2026-10-14 | - | tag/dedupe |
| SkillVault | huangluke89757/SkillVault @ec0ecaa | TS | 29 | 2026-09-30 | vlock | canonical dir + symlinks |
| skills-registry | nikships/skills-registry @9f57a4b | Go | 23 | 2026-09-28 | n/c | personal GH registry |
| skillbase | oujingzhou/skillbase @a882f49 | Go | 16 | no release | server sha256 | self-hosted, RBAC |
| skillnote | luna-prompts/skillnote @7ea2fc7 | TS | 67 | cli-v0.7.1 2026-07-27 | n/c | self-hosted registry |
| SkillsMaster | zhls-ayl/SkillsMaster @ee33e33 | Swift | 14 | 2026-06-30 | vlock | mac (CN) |
| skl | alexastrum/skl @c0ae3be | Go | 10 | no release | skills-lock.json, hash not compared | Go port of vercel |
| AiSkillBox | liutaos/AiSkillBox @a8c91ac | Rust | 8 | 2026-09-18 | - | MCP-driven |
| others ≤6★ | vorlaxen-labs/agent-skills, xiaxi626/dsh-skills-nexus, SoonIter/skills-package-manager, exa-studio/spm, useskillbase/spm, orthogonalhq/apm, kayaman/skillz + agentskills, gshahbazian/skillpm, ajac-zero/knack, thanhdt942/skillbox, dsdshcym/skill-set, BenedictKing/skill-master, zongwu233/skillctl + skills-store, GZL11/skillctl, dvlshah/skillctl, alexsmedile/apm, EdamAme-x/apm-lock, Hefaistos68/AgentPackageManager (NuGet), driftsys/upskill, sparfenyuk/agent-skills-cli | mixed | ≤6 | 2025–2026 | mostly none/vlock | thin installers |
| npm-only | skill-manager, harveyz-skill, tabernaculo, skillreg, @dealdeploy/skl, @corvus-tools/skill-manager, itismyskillmarket, skillsh, easy-skills, @metamask/skills, @iceinvein/agent-skills, secure-skills-cli (no repo), @playlist-tech/enterprise-skills (vercel fork, private registries d/o), skills-cli (repo 404) | JS | – | 2026 | not checked | npm search API 2026-10-26 |
| crates-only | agents-skills 0.28.1, agent-skill-installer 0.2.1, skillctl-cli 0.2.1, sm-skill-manager 0.3.2, skill-harness 0.1.3, agent-skills-rs 0.3.1 | Rust | – | 2026 | not checked | crates.io API |
| unverifiable | HappySkills (blog claims lock w/ sha256), lingengyuan/skillctl (CN blog claims `sync --frozen`) | ? | – | – | claimed | repo 404 |

Security scanners (not installers): cisco-ai-defense/skill-scanner (2,635★, 2.3.1), snyk/agent-scan (3,169★,
v0.6.9, cloud token), NVIDIA/SkillSpector (21.6k★, brew 2.13.1), openclaw/clawscan (npm 0.3.0),
Tencent/AI-Infra-Guard (v4.6.7, "Skills Scan"), crates `ramparts` 0.8.10, `oxidized-agentic-audit` 0.6.0,
`skillkit` 0.1.5 (WyattAu), alexgreensh/repo-forensics (v2.14.19), qualixar/skillfortify.

## 3. Per-tool detail (with citations)

### Agent Skills spec — agentskills/agentskills @69ef37e
- Frontmatter: `name` (≤64, lowercase-hyphen, = dir), `description` (≤1024), `license`, `compatibility`,
  `metadata` (string map), `allowed-tools` (experimental). No version, dependency or distribution field.
  `docs/specification.mdx` L27-32.
- `.agents/skills/` (project and user) called the "widely-adopted convention"; spec does not mandate locations;
  clients should log collisions and gate project skills behind trust. `docs/client-implementation/adding-skills-support.mdx` L45-57, L87, L91.
- `skills-ref` validator "for demonstration purposes only… not meant to be used in production"; NFKC on names, no
  invisible-char check. `skills-ref/README.md` L6; `skills-ref/src/skills_ref/validator.py` L37.
- No lock/packaging guidance (grep lockfile/package manager: none). So `requires:` (skillcask) is an extension
  outside the spec.

### Claude Code plugins — docs code.claude.com (fetched 2026-10-26), CHANGELOG @2eff7a8 (v2.1.310)
- Plugin sources: relative, `github`, `url`, `git-subdir` (take `ref`+`sha`), `npm` (version/range, registry),
  `archive` (url + `sha256`, since 2.1.224), `command` (since 2.1.229).
  https://code.claude.com/docs/en/plugins/marketplace-reference.md
- Integrity: opt-in `sha256` on archives only; npm via `npm pack --ignore-scripts` + integrity (CHANGELOG 2.1.275);
  git relies on commit checkout.
- No project lock. User-level `installed_plugins.json` records scope/path/version; commit recording fixed in
  2.1.277/2.1.280. https://code.claude.com/docs/en/plugins/loading.md
- Plugin dependencies: npm-semver ranges against `<plugin>--v<ver>` tags, conflict detection, `plugin prune`,
  `allowCrossMarketplaceDependenciesOn`. https://code.claude.com/docs/en/plugins/dependencies.md
- Org policy: `strictKnownMarketplaces` (owner/*, `hostPattern`, `pathPattern`), `blockedMarketplaces`,
  `disableSideloadFlags`, managed `enabledPlugins`, `CLAUDE_CODE_PLUGIN_SEED_DIR`. https://code.claude.com/docs/en/plugins/org.md
- Auth: non-interactive git with user's credential helper (Keychain, GCM) or ssh-agent; archives `headersHelper`.
  https://code.claude.com/docs/en/plugins/host-marketplace.md
- Auto-update background, off by default except official marketplaces; no diff/review; "the files you reviewed can
  change on disk". https://code.claude.com/docs/en/plugins/security.md
- Plugins "can execute arbitrary code": hooks, MCP, LSP, monitors, `command` source.
- Bidi/control chars rejected in marketplace/plugin **names** only. Publisher-side `renames` map (not consumer alias).
- Extras: `plugin init`, `validate --strict`, `eval`, `test`, `tag`, `--json`.

### Codex — openai/codex @970111f (rust-v0.164.0)
- Skill roots: repo `.agents/skills`, `~/.agents/skills`, deprecated `$CODEX_HOME/skills`, system cache.
  `codex-rs/ext/skills/src/host_roots.rs` L24-25, L96, L137-179; admin `/etc/codex/skills` per
  https://learn.chatgpt.com/docs/build-skills.
- `$skill-installer` = bundled skill with Python scripts, GH download (`--ref` default `main`), aborts if target
  exists; no lock/hash/update. `codex-rs/skills/src/assets/samples/skill-installer/SKILL.md`.
- Plugins: `codex plugin add|list|remove|marketplace …`; reads `.agents/plugins/marketplace.json` then
  `.claude-plugin/marketplace.json` (`core-plugins/src/marketplace.rs` L21-23). Sources Local/Git{ref,sha}/Npm
  (`--ignore-scripts`). No integrity (grep sha256/integrity/checksum in npm_source, plugin_bundle_archive,
  remote_bundle: none).
- Org policy `marketplaces.restrict_to_allowed_sources` (`core-plugins/src/marketplace_policy.rs` L50-75).

### `gh skill` — cli/cli @4f2cfe9 (v2.103.2); launched 2026-04-16 (https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/)
- Subcommands install/list/preview/search/update/publish (`pkg/cmd/skills/*`).
- Lock `~/.agents/.skill-lock.json` `lockVersion = 3`, comment: must match Vercel's lock version for interop;
  user-global, write-only. `internal/skills/lockfile/lockfile.go` L16-34, L95-129.
- Writes provenance into the installed SKILL.md `metadata` (`github-tree-sha` …), i.e. modifies skill text.
  `internal/skills/frontmatter/frontmatter.go` L65-95.
- Blobs fetched by SHA via REST, no local re-hash. `internal/skills/discovery/discovery.go` L918-943.
- `update` compares tree SHA; `--dry-run`, pinned skipped; no content diff. `pkg/cmd/skills/update/update.go` L134-137, L261, L303.
- Copies files per agent (48 IDs, `internal/skills/registry/registry.go`); collisions reported, no rename.
- Telemetry on; `GH_TELEMETRY`/`DO_NOT_TRACK` (`internal/telemetry/telemetry.go` L104-108).
- `publish`: spec validation, semver tag + release, immutable releases, secret-scanning check. `publish.go` L106-164.

### Gemini CLI — google-gemini/gemini-cli @cd1b45c (v0.65.0)
- `gemini extensions install <src> --ref --auto-update --pre-release --consent` (`packages/cli/src/commands/extensions/install.ts` L173-222); updates via `git ls-remote`/releases; no hash pin found.
- `gemini skills install|link|enable|disable|uninstall --scope user|workspace`; `.agents/skills` alias wins
  (`docs/cli/skills.md` L44-55). Extensions bundle hooks + MCP. Consent re-prompt when skills change.
  `allowedExtensions`, `blockGitExtensions` settings.

### Cursor / Kiro / OpenCode / Amp (closed, docs only)
- Cursor: skills from `.agents/skills`, `.cursor/skills`; GitHub import via `.cursor-plugin/marketplace.json`; no
  lock/pinning documented. https://cursor.com/docs/skills, https://cursor.com/docs/reference/plugins
- Kiro: `.kiro/skills`, IDE import from GH/local; "Powers" (plugin.json + skills + mcp.json), global-only; no pinning.
  https://kiro.dev/docs/skills/, https://kiro.dev/docs/powers/installation/
- OpenCode: reads `.opencode/skills`, `.claude/skills`, `.agents/skills`; V2 HTTP catalogs (`index.json`), per-skill
  permission globs; no lock. https://opencode.ai/docs/skills/, https://opencode.ai/v2/docs/skills/
- Amp: `amp skill add` GH/git/local, `--global`; server-side workspace skill repos; no lock. https://ampcode.com/docs/customize/skills

### obra/superpowers @2ce8aa1 (v7.0.1)
- No own installer; ships per-host manifests (`.claude-plugin`, `.codex-plugin`, `.cursor-plugin`,
  `gemini-extension.json`, …) README L52-200. Runs a SessionStart hook (`hooks/hooks.json`).

### vercel `skills` / skills.sh — vercel-labs/skills @a80e4c9 (v1.7.4)
- Commands add/find/list/use/check/update/remove/init, `experimental_sync`, `experimental_install`; `--json`.
  `docs/commands.md`. `add-skill` is a bin alias (package.json).
- `skills-lock.json`: `{source, ref?, sourceType, skillPath?, computedHash, …}`; hash = sha256 over path+content.
  `src/local-lock.ts` L15-50, L154-170. `ref` = user-typed ref, never resolved commit (`src/add.ts` L1310-1323).
- Hash used only in update detection (`src/update.ts` L600, L649-654, L938); `runInstallFromLock` has no hash
  compare (`src/install.ts` L20-110).
- Install shows Gen/Socket/Snyk audit table from `skills.sh/tele/audit`, never blocks (3 s timeout).
  `src/telemetry.ts` L107-137; `src/add.ts` L151-200; https://skills.sh/audits
- Telemetry to `skills.sh/tele/t`; `DISABLE_TELEMETRY`/`DO_NOT_TRACK`. `src/telemetry.ts` L141-175.
- Symlink or `--copy`; junctions on Windows (`src/installer.ts` L290). Reads Claude plugin manifests
  (`src/plugin-manifest.ts`). Strips terminal escapes (`src/sanitize.ts`), not bidi/zero-width.
- skills.sh: leaderboard by install counts, search, topics (https://skills.sh, 2026-10-26).
- Grep @a80e4c9 src/: `semver` 0, `cooldown|minimumReleaseAge` 0, `allow-?sources` 0, `composer|packagist` 0,
  `bidi|zero-width|u200b|u202e` 0.

### APM — microsoft/apm @2920043 (v0.35.0)
- `apm.lock.yaml`: resolved_commit, tag, constraint, `content_hash`, `deployed_file_hashes`, declared_license.
  `docs/src/content/docs/reference/lockfile-spec.md` L10-60, L102-271.
- Hash enforced: mismatch raises "Content hash mismatch … supply-chain attack" and deletes download
  (`src/apm_cli/install/sources.py` L858-884); installed copies re-verified (`install/phases/download.py` L85-120).
- `install --frozen` (`reference/cli/install.md` L49); `audit --ci` SARIF/JSON (`reference/cli/audit.md`).
- Ranges `^`, `~`, `>=`, `x` on git tags, prereleases excluded (`reference/manifest-schema.md` L537-596).
- `apm-policy.yml` auto-discovered from git remote: dependency allow/deny, registry_source, MCP allow/deny,
  `scripts: deny`, inheritance (allow intersect, deny union). `reference/policy-schema.md` L16-291.
- Hidden-Unicode scanner (tag chars, bidi, zero-width), blocks critical unless `--force`; `audit --strip`.
  `src/apm_cli/security/content_scanner.py` L3-55.
- Hooks/bin/MCP from deps blocked until `apm approve` (`reference/cli/approve.md`); lifecycle scripts need
  `apm lifecycle trust`.
- Auth: `GITHUB_APM_PAT_{ORG}`, `GITHUB_TOKEN`, `gh auth token`, git credential helper; GitLab/ADO/Bitbucket via
  helper. `getting-started/authentication.md` L7-45.
- `update` prints add/update/remove plan, consent default No; refs only, no text diff (`reference/cli/update.md`
  L16-40). Cooldown: grep `release_age|min_age|cooldown` in src → cache pruning only.
- GitHub Action microsoft/apm-action@d723bb6. Renovate native `apm` manager (renovatebot/renovate
  `lib/modules/manager/apm`, added 6d747ea8ff, #44390, 2026-09-02). Dependabot `apm` PR
  dependabot/dependabot-core#16382 merged 2026-10-12 (manifest only; availability on github.com unverified).

### Tessl — tesslio/cli @2a62724 (README+LICENSE only, proprietary); npm @tessl/cli 0.118.0 is a binary-download shim
- `tessl install workspace/plugin[@ver] | github: | git@ | file:`, `--global`, 11 agents. https://docs.tessl.io/reference/cli-commands.md
- `tessl.json` exact versions; "vendored" vs "managed" mode. No lock/hash in docs. https://docs.tessl.io/reference/configuration.md
- Snyk security scores, `tessl review run security --fail-on high`, org/workspace install policy incl. git
  host/org allowlist (https://docs.tessl.io/tutorials/protecting-against-insecure-skills.md L31-63) — but CLI
  reference says installs are never blocked (`cli-commands.md` L325): docs contradict.
- Telemetry `shareUsageData` default true (configuration.md L799-824). Evals, `skill new/lint/publish`, MCP gateway.

### ClawHub — openclaw/clawhub @e726f3c (v0.23.3)
- `.clawhub/lock.json`: version, installedAt, source, scan status, trust label, pinned — no hash
  (`packages/clawhub/src/schema/schemas.ts` L20-39). Post-install fingerprint in `origin.json`, not checked against
  registry; plugin artifacts do check sha256 (`commands/packages.ts` L330-332).
- `update` refuses on local fingerprint mismatch; `pin/unpin` (`docs/cli.md` L171-191). Publish auto patch bump;
  VirusTotal + moderation server-side (`docs/moderation.md` L95-108). Search by downloads/rating; stars.
- Telemetry: install events when logged in, opt-out (`docs/telemetry.md`).

### tech-leads-club/agent-skills @738451e
- Catalog via npm `@tech-leads-club/skills-catalog` on jsDelivr/unpkg (`libs/core/src/lib/services/registry.service.ts` L111-118);
  "Checksum mismatch" on download (L342-349). Lock w/ contentHash, atomic writes, removal audit log
  (`lockfile.service.ts` L16-30; SECURITY.md L84-102). Snyk agent-scan in release CI. No semver/frozen/private.

### iflytek SkillHub @9e76502
- Self-hosted: semver + beta/stable tags, namespaces with RBAC, review workflow, audit log, scoped tokens,
  ClawHub-compatible API (README L63-83). CLI verifies fingerprint (`cli/src/services/install-service.ts` L159-167);
  no project lock. OAuth device flow. Bundled Cisco skill-scanner.

### ai-rulez — Goldziher/ai-rulez @291b11f (v5.7.0, 2026-10-26)
- Lock `.ai-rulez/ai-rulez.lock`: commit + sha256 tree digest per installed skill/item/output; `generate` fails on
  digest mismatch; `--locked/--frozen`; `lock --check/--diff/--outdated`. `docs/lockfile.md` §"What is pinned",
  §"Commands" L630-711; `docs/installed-skills.md`.
- Ranges `^1.2`, `~2.1.0`, `>=1.4.0 <2.0.0`, `1.x || 3` against tags, `tag_prefix` for monorepo tags.
  `docs/lockfile.md` L212-240.
- `min_release_age = "7d"`, release time from forge or first sighting (`internal/releasetime/seen.go` L2;
  `cmd/commands/update.go` L59; `internal/lockrun/lockrun.go` L197). Org policy enforces it as a floor
  (`sources.min_release_age` "the longer age … a younger per-source age including "0"" → AR740;
  `docs/policy.md` L172-173, L304-305). Same idea as skillcask's enforced cooldown.
- Policy `[sources] allowed_hosts` outside the repo (`AI_RULEZ_POLICY`, `/etc/ai-rulez/policy.toml`), tighten-only.
  `docs/policy.md` L3, L169, L189.
- Hidden-character lint `internal/lint/ar_hidden.go`; approval diffs escape zero-width as `\u{XXXX}`
  (`docs/approvals.md` L66).
- Approvals bound to digest; `approve --diff` shows file list/sizes/scan, not text; docs: "The item digest does
  not tell you what changed … Pair it with the normal source diff" (`docs/lockfile.md` L799-814).
- `name_prefix` namespaces clashing skill dirs (CHANGELOG 5.5.0 L335). Lock signing (Sigstore), SBOMs
  (`docs/lockfile.md` §"Signing the lock" L536). GitHub Action (`action.yml`). Telemetry opt-in, local.
- Scope: generates rules/commands/hooks/MCP for 52 harnesses; installs hooks (runs code by design).

### rulesync — dyoshikawa/rulesync @d2fdee0 (v41.0.0)
- `rulesync.lock`: requested ref, resolved commit, sha256 per skill; npm lock with tarball integrity.
  Hash check `src/lib/sources.ts` L1874 (warning; hard fail under `--frozen`, L1291).
- Ranges intentionally out of scope (`npm-client.ts` L258). `install --outdated` exit 0/1/2 + `--json`.
- Confusable/hidden chars checked in skill **names** (`utils/confusable-names.ts`); body not found.
- Generates native files for ~60 tools; Windows e2e in CI.

### netresearch/composer-agent-skill-plugin @20d15d6 (v2.1.1)
- Only other Composer-based tool. A Composer plugin (needs `allow-plugins`, i.e. executes in Composer) for PHP
  projects; packages typed `ai-agent-skill`. Direct sources locked in `composer.skills.lock` with commit + sha256;
  "Checksum mismatch" (`DirectSkillsCoordinator.php` L165, L190); stale-lock error (L76).
- Composer constraints via composer/semver; `skills:outdated --strict` exits 1.
- Does not link into agent dirs: writes an AGENTS.md XML index (openskills style); skills stay in `vendor/`.
- Bidi/control chars checked in **description** only (`SkillFrontmatterValidator.php` L35). Name clash = hard error.

### qvr — try-agora/qvr @7178391 (v0.30.0)
- `qvr.lock`: commit, subtreeHash, scan verdict, commit author. Drift is an error by default, `--allow-drift`
  to warn (`cmd/sync.go` L72-79, L769-800); hash `internal/skill/verification.go` L212-221.
- `--locked/--frozen/--check` (uv semantics) `cmd/sync.go` L76-90. No ranges; `switch --latest` (cmd/switch.go L57-58).
- Unicode: zero-width, bidi, Tag chars = critical (`internal/security/unicode.go` L15-19); SARIF; `trust pin`
  commit-author allowlist (`cmd/trust.go`); `--as` alias (`cmd/add.go` L121); `--vendor`; `audit` (local OTel
  spans from agent sessions), `ui`.
- `qvr diff` = git diff of local edits, not upstream (`cmd/diff.go` L24-26).

### comountainclimber/skillpm @2ac80df (v0.1.1)
- `install` recomputes tree sha256 per lock entry, exit 1 on mismatch (`internal/cli/cli.go` L218-226); `ci` frozen
  by default (L321-348); regex audit blocks `add` (SKILL-001…008); GitHub Action (`action.yml`). Lock only, no ranges.

### skills-lock — luisalima/skills-lock @4e37719 (0.1.0)
- sha256 over sorted paths+contents (`src/integrity.mjs` L8-26); compared **only** under `--frozen`
  (`src/install.mjs` L38-40, L68-87); plain install silently rewrites. Transport allowlist, refuses symlinks, empty git hook template.

### nodus — nodus-rs/nodus @4c16d4e (v0.17.0)
- `nodus.lock` digest/install_digest (`src/lockfile.rs` L58, L99, L526-532); `--locked/--frozen` regenerate and bail
  on difference (`src/resolver/runtime.rs` L1183-1195); `semver::VersionReq` on tags (`src/git.rs` L692).
- Bundles hooks + MCP, generates Claude/Codex marketplaces; `review` calls LLM APIs (`src/review.rs`).

### Others in 2a (short)
- craft @38a686a: integrity checked `internal/cli/install.go` L448-449; transitive deps; vendors `forge/`.
- grimoire @998c8e2: lock checksum = sha256 of SKILL.md only (`cmd/install.go` L1160), never compared; Masterminds
  ranges (`internal/resolver/resolver.go` L13-55); OCI storage **not found** in code (web summary was wrong).
- rosie @61cc358: lock has no content hash (`src/lockfile.rs` L1-42); strips invisible Unicode + md comments
  (`src/sanitize.rs` L1-30, called `src/install.rs` L19, L91); unified diff in update audit log (`src/audit.rs` L53-55, L129-138).
- pspm @e97682e: sha256 check `src/commands/install.ts` L541-553, mismatch → `continue` unless `--frozen-lockfile`.
- SPM skillpkg/spm @fa0fc1d: checksum written not compared; Sigstore at publish (`cli-go/cmd/publish.go` L151-173), `spm verify`.
- skpm-sh/cli @16be416: `postInstall` shell commands (`src/post-install.ts` L20-28), telemetry `skpm.sh/t` (`src/telemetry.ts` L1-2).
- pixi-skills @35711ca: symlinks `share/agent-skills/` from pixi envs (`pixi_skills/backend.py` L52-59); cooldown
  via pixi `exclude-newer` (`7d`) https://pixi.prefix.dev/latest/reference/pixi_manifest/.
- agent-skills-cli (Karanjot786) @465cad3: lock in user home (`src/core/skill-lock.ts` L14); `frozen` ignores failed
  checkout and never compares hash (`src/cli/commands/frozen.ts` L45-80); 36-rule blocking scanner incl. Unicode
  UC001-006 (`src/core/scanner-rules.ts` L308-345); cred helper + netrc (`src/core/git-auth.ts`); `exec` runs
  scripts (`src/core/executor.ts`).
- openskills @57d933a: `git clone --depth 1`, no ref (`src/commands/install.ts` L157); writes AGENTS.md
  `<available_skills>`; no lock.
- skills-npm @37a3aff: merging into `skills experimental_sync` (README); conflict priority ladder (`SPEC.md`).
- qntx/skill @c9843b5: Rust port; telemetry `add-skill.vercel.sh/t` (`skill/src/telemetry.rs` L5-28); `doctor`, completions.
- skillman @77d70bc: runs `npx skills add` per entry (`src/skills.ts` L82-111); schema has no ref/hash.
- rohitg00/skillkit @d2e5c34: `add --scan` blocks HIGH incl. `scanner/rules/unicode.ts`; `translate` to `.mdc`.
- rolecraft @4c89c0b: README "`ci` verifies content, it does not pin sources … There is no `--frozen` mode";
  strips zero-width before scan (`utils/security.js` L403); `rollback`, completions.
- skillshare @7ed64d4: lock {source, commit, tree_hash} (`internal/install/lock.go` L18); doctor integrity
  (`cmd/skillshare/doctor.go` L921); GH Action.
- skpm (domehahn) @a9d53b7: `--frozen-lockfile` (`internal/cli/fetch.go` L24), digest check
  (`internal/installer/installer.go` L115), `internal/attestation`.
- kasetto @819c72a: lock hash (`src/lock.rs` L19), `--locked/--frozen` (`src/commands/sync/mod.rs` L45).
- skillmod @b2c4442: Go `dirhash` (`internal/dirhash/dirhash.go` L20).
- skillfold @34a42d9: integrity compare `src/install.ts` L228, L271; `install --frozen`.
- bapm @56ad727: CI auto-frozen (`packages/core/src/modules/Install/ciFrozen.ts`), CycloneDX export.
- vrothberg/skillctl @7e66462: OCI digests; README "Renovate and Dependabot can detect OCI image references".

## 4. Gaps: they have, skillcask lacks (Q2)

skillcask already has (so not gaps): `search` (Packagist API filtered by `type=ai-agent-skill`, name match on
other Composer repos), `remove`, `info`, `status`, `doctor --fix`, `init` (manifest only), and
`skillcask-<other>` PATH plugins (`docs/specs/2026-10-19-skillcask-v1.md` §Commands @961f568). JSON output is a
declared non-goal (`docs/specs/2026-10-20-cli-output.md` §Non-goals).

Discovery and UX
- Popularity-ranked catalog/leaderboard, cross-source search: vercel skills (`find`, skills.sh install counts), gh skill (`search` via code search),
  ClawHub (downloads/rating/stars), agent-skills-cli (marketplace, fzf), qvr, pspm, SPM, grimoire, skillfile
  (`--min-score`), skillfish, asm, aweskill, APM (`find/search`), Tessl.
- Interactive TUI pickers / multi-select: vercel skills, gh skill, tech-leads-club, skillkit `ui`, skillfile.
- `preview` / `use` before install: gh skill `preview`, vercel `use`, agent-skills-cli `sandbox`.
- Web UI / desktop GUI: qvr `ui`, kitter, xingkongliang/skills-manager (6.9k★), HarnessKit, many mac/Tauri apps.
- Shell completions: qntx/skill, rolecraft. Self-update: qvr (checksum-verified), APM, qntx/skill.
- `--json` output (skillcask non-goal): vercel skills, Claude plugins, Codex plugins, rulesync, asm, skillfish, qvr, kasetto.
- Token/context-cost reporting: agent-skills-cli (`list --table`, `budget`), asm (`stats --tokens`).

Authoring
- Scaffolding a new skill (skillcask `init` only writes skills.toml): vercel skills, Claude `plugin init`, qvr `create`, pspm/SPM/skpm `init`, Tessl `skill new`, asm, skillkit.
- Evals/tests of skills: Claude `plugin eval/test`, Tessl evals, asm `eval`, rolecraft `test`, ai-rulez `eval/judge`, SPM `test`.
- Eject/edit and publish back upstream: qvr `edit`, skillcrew `propose` (opens PR), gh skill `publish --fix`.
- Publish to GitHub release with tag + immutable release + secret scanning: gh skill `publish`; `plugin tag` (Claude).

Formats and scope
- Native plugin bundles (hooks, MCP, LSP, commands, agents): Claude Code, Codex, Gemini, Cursor, Kiro; APM, nodus,
  rulesync, ai-rulez, kasetto, skillshare, HarnessKit, rolecraft, agent-skills-cli (MCP install). skillcask
  excludes these on purpose (data-only invariant).
- Generating per-agent native formats (rules, `.mdc`, AGENTS.md index): rulesync (~60), ai-rulez (52), skillkit
  `translate`, openskills and composer plugin (AGENTS.md `<available_skills>`), APM `compile`.
- Copy vs symlink choice: vercel `--copy`, gh skill (copies), tech-leads-club, skillkit, skl, skm (hard/reflink).
- Vendor mode (commit real files): qvr `--vendor`, Tessl "vendored", craft `forge/`.
- Profiles/presets: rolecraft, kitter, ai-rulez, kasetto `extends`.
- Admin/system scope (`/etc/...`): Codex `/etc/codex/skills`; managed settings in Claude Code.

Sources
- Azure DevOps / Bitbucket / any git URL: vercel (Azure Repos, git), APM (ADO, GitLab, generic git), rulesync,
  ai-rulez, qvr, nodus, Gemini, Codex. (skillcask: GitHub + Composer only; GitLab via its Composer registry.)
- Local path sources: vercel, APM, nodus, qvr, skills-lock (`file:`), gh skill `--from-local`, rulesync, Tessl, Amp, Gemini `link`.
- Direct tarball/zip/SKILL.md URL: vercel, Claude `archive` (with sha256), pspm well-known.
- `/.well-known` (RFC 8615) discovery: vercel skills, pspm.
- npm as a skill transport: vercel `experimental_sync`, skills-npm, skillpm (npm), rulesync, Claude/Codex npm sources, rosie.
- OCI registries: vrothberg/skillctl, ai-rulez publish.
- conda channels: pixi-skills.

Security and supply chain
- Install-time security scanner that blocks: APM (hidden Unicode, critical blocks), agent-skills-cli (36 rules),
  qvr (15 categories, SARIF), comountainclimber/skillpm, rohitg00/skillkit, rolecraft (score <70 blocks),
  vercel (partner audit display, non-blocking), Tessl (Snyk scores), ClawHub (VirusTotal server-side),
  SkillHub (Cisco scanner). skillcask only warns on invisible Unicode.
- Prompt-injection / malicious-pattern rules (curl|bash, ~/.ssh, "ignore previous instructions"): agent-skills-cli,
  comountainclimber/skillpm, qvr, rolecraft, standalone scanners (Cisco skill-scanner, Snyk agent-scan, NVIDIA SkillSpector).
- SARIF output: APM `audit --ci`, qvr, Cisco skill-scanner.
- Advisory database / `audit` of installed skills: agent-skills-cli (`audit --fail-on`, agentskills.in advisories).
- Stripping invisible Unicode (not just warning): rosie, APM `audit --strip`.
- Executable/approval gates: APM `approve`, ai-rulez digest-bound reviewer approvals, composer plugin per-package `allow-skills`.
- Signing/provenance: SPM (Sigstore at publish, `spm verify`), ai-rulez (Sigstore-signed lock, in-toto),
  domehahn/skpm (attestation pkg), gh skill (provenance frontmatter + immutable releases), qvr (commit-author trust pins).
- SBOM: ai-rulez (CycloneDX/SPDX), bapm (CycloneDX). License tracking: APM (`declared_license` in lock).
- Per-file deployed hashes + drift detection of hand edits: APM (`deployed_file_hashes`), nodus `install_digest`.
- Per-skill permission globs at runtime: OpenCode V2.

Automation
- GitHub Action: microsoft/apm-action, comountainclimber/skillpm, skillshare `setup-skillshare`, ai-rulez, Cisco scanner.
- Renovate/Dependabot: APM only (native Renovate manager; Dependabot PR merged). Vercel lock: open requests only
  (renovate discussion #41861, dependabot issue #14739). skillctl via OCI refs.
- Auto-update channels: Claude Code (background), Gemini `--auto-update --pre-release`.
- Seed dir for CI/containers: Claude `CLAUDE_CODE_PLUGIN_SEED_DIR`.

Management
- `prune`/`clean`: APM, Claude `plugin prune`, nodus `clean`, agent-skills-cli `update --prune`, qvr `cache prune`.
- Rollback / trash: rolecraft `rollback`, skillshare trash.
- Usage analytics: qvr `audit` (local OTel spans, A/B compare across versions, idle-skill report); Claude org OTel.
- Ratings/stars/downloads: ClawHub, skills.sh.
- Monorepo/recursive runs: ai-rulez; npm workspaces via skillpm (npm).
- Two versions side by side: qvr `--as`.
- Enable/disable without uninstall: Codex config, Gemini `skills enable/disable`, rolecraft.
- Programmatic API/SDK: rosie (typed JS/wasm), APM (Python), ai-rulez MCP server (`install_skill` tool), nodus.
- MCP server exposing skill management to the agent: ai-rulez, AAS Core, skillport, AiSkillBox, SPM.

## 5. What skillcask has that nobody else does

Checked by grep across the cloned repos listed above (vercel, gh, codex, gemini, apm, clawhub, tech-leads,
skillhub, ai-rulez, rulesync, composer plugin, qvr, skillpm×2, skills-lock, nodus, craft, grimoire, rosie, pspm,
SPM, skpm×2, pixi-skills, kasetto, skillmod, skillshare, skillfold, agent-skills-cli, openskills, skills-npm,
qntx/skill, + 62 long-tail clones) and the Claude/Cursor/Kiro/OpenCode/Amp/Tessl docs.

Unique (no evidence elsewhere):
1. **Composer repositories as the skill source from a standalone, language-neutral tool** (Packagist, GitLab
   Composer registry, Satis, static repo). grep `composer|packagist`: 0 hits in APM `src`, vercel `src`, all
   slice-4 clones, all 62 long-tail clones. Only netresearch/composer-agent-skill-plugin uses Composer, and it is a
   PHP Composer plugin (runs inside Composer, needs `allow-plugins`, no agent-dir linking). skillcask reuses its
   package convention (`type: ai-agent-skill`, D3) and Composer `auth.json` (D8), so packages are shared.
2. **`publish` that builds a static Composer repository from a monorepo of skills.** Not found anywhere; other
   publish paths are git tags (qvr, gh skill, ai-rulez), hosted registries (ClawHub, pspm, SPM, Tessl, APM REST), npm, OCI.
3. **Review diff of SKILL.md text before an update is applied** (`diff`, `update --diff`). Not found: APM update
   shows a ref plan only; gh skill/vercel compare hashes; ai-rulez `approve --diff` lists files+scan and its docs
   say pair the digest with a normal source diff; qvr `diff` shows local edits; rolecraft/agent-skills-cli `diff`
   compare two skills, not an update; Gemini re-prompts consent without a diff. Nearest: rosie writes a unified diff
   to an audit log **after** updating.
4. **Skill dependencies declared in SKILL.md frontmatter (`requires:`).** Others with deps keep them in a separate
   manifest (APM `apm.yml`, nodus, craft, grimoire, pspm, Claude plugin.json, Composer `require`). skpm-sh `dependsOn`
   location not traced. The spec has no such field (§3).
5. **The combination in one static binary with no runtime**: hash lock verified on install + frozen + Composer
   semver ranges + cooldown + org-enforced source policy + data-only (never runs package code) + no telemetry. The
   two nearest (APM, ai-rulez) both run package hooks/scripts by design (behind approval), APM needs Python.

Not unique (exists elsewhere, cite when positioning):
- sha256/tree-hash lock verified on install + frozen: APM, ai-rulez, rulesync, qvr, comountainclimber/skillpm,
  craft, nodus (via lock compare), skillfold, kasetto, skillmod, domehahn/skpm, composer plugin (direct sources),
  tech-leads-club and SkillHub (registry hash, no frozen).
- Semver ranges: APM, ai-rulez, nodus, grimoire, pspm, SPM, composer plugin, Claude plugin deps.
- Cooldown / min-release-age: **ai-rulez** (`min_release_age`, org floor via policy — same semantics as skillcask's
  enforced cooldown); pixi-skills via pixi `exclude-newer`. Absent from APM, vercel, gh, Claude, Codex and all others checked.
- Org allow-sources policy: APM `apm-policy.yml`, ai-rulez `allowed_hosts`, Claude `strictKnownMarketplaces`,
  Codex `restrict_to_allowed_sources`, Gemini `allowedExtensions`, Tessl (docs), skillcrew (team blocked list).
- Invisible-Unicode detection: APM (blocks), qvr, ai-rulez, agent-skills-cli, rohitg00/skillkit, rosie (strips),
  rolecraft (strips before scan). Name/description-only checks: Claude Code, rulesync, composer plugin.
- Consumer-side rename/alias: qvr `--as`, ai-rulez `name_prefix`, APM `alias`, asm `--name`.
- `outdated --strict`-style CI gate: composer plugin `skills:outdated --strict`, rulesync `--outdated`,
  ai-rulez `lock --outdated`, gh skill `update --dry-run` exit code.
- git-credential/keychain auth: APM, ai-rulez, vercel, Claude Code, agent-skills-cli, qvr.
- Canonical `.agents/skills` store + per-agent links: vercel skills (symlinks/junctions), kitter, SkillVault, aweskill, skillshare.
- No telemetry: true of APM, ai-rulez (opt-in local), qvr, skills-lock, comountainclimber/skillpm, rolecraft. On by
  default in vercel skills, gh, Tessl, ClawHub (logged in), agent-skills-cli, skillfish, skpm-sh, qntx/skill, gentle-ai.
- `--global` personal scope: nearly all.

Caveats
- ai-rulez released v5.7.0 the same day as this check and ships fast (5.0→5.7 in two weeks); re-check before
  making public uniqueness claims about cooldown/policy/diff.
- Closed-source tools (Claude Code, Cursor, Kiro, Amp, Tessl) checked from docs only.
- Dependabot `apm` support merged upstream; whether it is enabled on github.com was not verified.

## 6. Sources

Spec and native
- https://github.com/agentskills/agentskills @69ef37e (`docs/specification.mdx`, `docs/client-implementation/adding-skills-support.mdx`, `skills-ref/`)
- https://code.claude.com/docs/en/plugins/marketplace-reference.md, …/loading.md, …/dependencies.md, …/org.md,
  …/host-marketplace.md, …/security.md (fetched 2026-10-26); https://github.com/anthropics/claude-code/blob/2eff7a8/CHANGELOG.md (v2.1.310)
- https://github.com/openai/codex @970111f (rust-v0.164.0); https://learn.chatgpt.com/docs/build-skills; https://learn.chatgpt.com/docs/plugins
- https://github.com/cli/cli @4f2cfe9 (v2.103.2); https://cli.github.com/manual/gh_skill_install; https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/
- https://github.com/google-gemini/gemini-cli @cd1b45c (v0.65.0)
- https://cursor.com/docs/skills; https://cursor.com/docs/reference/plugins; https://kiro.dev/docs/skills/; https://kiro.dev/docs/powers/installation/;
  https://opencode.ai/docs/skills/; https://opencode.ai/v2/docs/skills/; https://ampcode.com/docs/customize/skills
- https://github.com/obra/superpowers @2ce8aa1 (v7.0.1)

Package managers and registries
- https://github.com/vercel-labs/skills @a80e4c9 (v1.7.4); https://skills.sh; https://skills.sh/audits
- https://github.com/microsoft/apm @2920043 (v0.35.0); https://github.com/microsoft/apm-action @d723bb6
- https://docs.tessl.io/reference/cli-commands.md; https://docs.tessl.io/reference/configuration.md;
  https://docs.tessl.io/tutorials/protecting-against-insecure-skills.md; https://github.com/tesslio/cli @2a62724; npm @tessl/cli 0.118.0
- https://github.com/openclaw/clawhub @e726f3c (v0.23.3)
- https://github.com/tech-leads-club/agent-skills @738451e
- https://github.com/iflytek/skillhub @9e76502
- https://github.com/Goldziher/ai-rulez @291b11f (v5.7.0)
- https://github.com/dyoshikawa/rulesync @d2fdee0 (v41.0.0)
- https://github.com/netresearch/composer-agent-skill-plugin @20d15d6 (v2.1.1)
- https://github.com/try-agora/qvr @7178391 (v0.30.0)
- https://github.com/comountainclimber/skillpm @2ac80df; https://github.com/sbroenne/skillpm @1dadf71
- https://github.com/luisalima/skills-lock @4e37719; https://github.com/nodus-rs/nodus @4c16d4e; https://github.com/erdemtuna/craft @38a686a
- https://github.com/jeffreytse/grimoire @998c8e2; https://github.com/rosieskills/rosie @61cc358; https://github.com/anyt-io/pspm-cli @e97682e
- https://github.com/skillpkg/spm @fa0fc1d; https://github.com/skpm-sh/cli @16be416; https://github.com/domehahn/skpm @a9d53b7
- https://github.com/pavelzw/pixi-skills @35711ca; https://pixi.prefix.dev/latest/reference/pixi_manifest/
- https://github.com/pivoshenko/kasetto @819c72a; https://github.com/huija/skillmod @b2c4442; https://github.com/runkids/skillshare @7ed64d4;
  https://github.com/byronxlg/skillfold @34a42d9; https://github.com/Sdju/bapm @56ad727; https://github.com/vrothberg/skillctl @7e66462;
  https://github.com/eljulians/skillfile @c37d7ca
- https://github.com/Karanjot786/agent-skills-cli @465cad3; https://github.com/numman-ali/openskills @57d933a;
  https://github.com/antfu/skills-npm @37a3aff; https://github.com/qntx/skill @c9843b5; https://github.com/pi0/skillman @77d70bc
- https://github.com/rohitg00/skillkit @d2e5c34; https://github.com/luongnv89/asm @10d9bac; https://github.com/knoxgraeme/skillfish @7f66d03;
  https://github.com/rolecraft-sh/rolecraft @4c89c0b
- Long-tail repos at the SHAs in §2b.

Bots and scanners
- https://github.com/renovatebot/renovate/tree/548f5c77e4/lib/modules/manager/apm (added 6d747ea8ff); https://github.com/renovatebot/renovate/discussions/41861
- https://github.com/dependabot/dependabot-core/pull/16382; https://github.com/dependabot/dependabot-core/issues/14739
- https://github.com/cisco-ai-defense/skill-scanner @de5fcf0; https://github.com/snyk/agent-scan @a8c8c58; https://github.com/openclaw/clawscan @1e9057b;
  https://github.com/Tencent/AI-Infra-Guard @7457acf

Registries queried: npm search API, crates.io API, pypi.org JSON API, https://formulae.brew.sh/api/formula.json (all 2026-10-26).
Discovery-only (secondary, not cited for facts): https://agentskillshub.top/best/skill-management-tools/, dev.to articles, https://happyskills.ai/blog/the-lock-file-for-ai-agent-skills/, https://www.v2ex.com/t/1243561.
