# Spec: skillcask — a lockfile-first package manager for AI agent skills

Date: 2026-10-19. Status: v1.

## Problem

Agent skills (a directory with `SKILL.md`, read by Claude Code, Codex, Junie and others) are
copied into repositories by hand or by tools that do not freeze what they install.

- **Vercel Skills CLI** (`npx skills`, v1.7.4, source checked at `vercel-labs/skills@a80e4c9`):
  writes a project `skills-lock.json` with `source`, `ref` (branch or tag) and `computedHash`
  (sha256 of the files), but `experimental_install` re-fetches from `ref`, not from a commit, and
  never checks `computedHash` (`src/install.ts`). A moved tag or branch installs different content
  silently. No semver for git sources, `update` takes the newest, no CI drift check: `skills
  check` is an alias of `update` and changes the install (`src/cli.ts:420`). Needs Node >= 22.20;
  anonymous telemetry on by default.
- **`netresearch/composer-agent-skill-plugin`** (MIT, v2.1.1): a Composer plugin with a package
  convention (`"type": "ai-agent-skill"`, 57 such packages on Packagist), semver, a lock whose
  checksums it now verifies, a per-package trust map, and an `AGENTS.md` index instead of agent
  skill directories. Works only where Composer and PHP are present.
- **microsoft/apm** (v0.35.0): commit pin, sha256 that fails on mismatch, `install --frozen`,
  semver and transitive dependencies. No release cooldown; packages may ship hooks and MCP
  servers (behind an approval gate); needs Python.
- **rulesync** (v41.0.0): commit pin, per-skill sha256 checked under `--frozen`, `--outdated`. No
  semver, no cooldown.
- **Goldziher/ai-rulez** (v5.7.0): digest lock, `--frozen`, `min_release_age` with an
  organisation floor, a Sigstore-signed lock. Packages may carry hooks and scripts.
- **Tessl CLI** (v0.118.0, proprietary): semver, commit pin, an organisation release-age policy;
  no content hash, no frozen mode, telemetry on by default (it may include file contents).
- **ClawHub** (v0.23.3): registry with VirusTotal and LLM scanning; the lock has no hash and there
  is no frozen mode.
- **`gh skill`** (GitHub CLI 2.103, preview): a user-global lock in the Vercel format, no hash
  check, and it edits `SKILL.md` on install.
- **In-house sync scripts**: semver per skill, committed lock, sha256 per package, CI drift check — but bash, tied to one
  GitLab instance and its Generic Package Registry layout.

Supply-chain security practice asks for a committed lockfile, deterministic installs that fail on drift, pinned versions, a cooldown on
freshly published versions, and no install-time code execution. Several tools now lock by
content hash and install frozen; none combines a content-hash lock, a frozen install, a
release-age cooldown, a text diff of updates and data-only packages in one static binary without
a runtime. The 2026-10-26 survey behind this list is in `docs/research/`.

## Goal

One static binary that installs agent skills the way Composer or Cargo install libraries: a
manifest with version constraints, a committed lock with content hashes, frozen installs in CI,
and links into every agent's skill directory. Skills are distributed through the Composer
repository protocol, so Packagist serves public skills and GitLab's Composer registry (or any
static Composer repository) serves private ones, without a new registry.

Success: a repository in any language runs `skillcask install --frozen` in CI and gets
byte-identical skills to the ones committed in the lock, or a non-zero exit.

## Non-goals (v1)

- Composer `require` of skill packages (ignored; skills declare dependencies in `SKILL.md`, D16).
- ~~Installing from plain git repositories or URLs other than GitHub (see D11).~~ Plain git
  repositories over HTTPS since D30 (2026-10-26); other URLs still not.
- Trust prompts: an entry in `skills.toml` is the decision.
- Running any code from a package (scripts, hooks, plugins). Never, not only in v1.
- GitLab Generic Package Registry archive layouts (`.skill` archives + `CATALOG.md`).
- A hosted registry or web UI.
- Telemetry.

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Rust, single static binary. | No runtime in the target repository (PHP, Ruby, .NET, JS alike); one artefact to sign and verify. |
| D2 | Composer repository protocol v2 is the only backend (plus inline `packages`, D12). | Packagist (public), GitLab Composer registry, Satis and Private Packagist (private) all speak it; one client covers them. |
| D3 | Package convention from netresearch: `"type": "ai-agent-skill"`, `extra.ai-agent-skill`. | Existing packages install unchanged; no competing convention. |
| D4 | Manifest `skills.toml`, lock `skills.lock`, both TOML, project root. | Language-neutral, comments allowed, familiar from Cargo. |
| D5 | Canonical install directory `.agents/skills/<name>`; other agents get relative symlinks. | Codex reads `.agents/skills` directly; Vercel uses the same canonical place; one copy on disk. |
| D6 | The lock pins version, commit reference and two sha256 hashes; `install` verifies both. | Closes the gap in Vercel's lock: what is installed is what was reviewed. |
| D7 | Cooldown `min-release-age` (default 3 days) applies to `add` and `update`. | Most malicious releases are pulled within days; installing from the lock is unaffected. |
| D8 | Authentication reads Composer's `auth.json` / `COMPOSER_AUTH`. | Existing GitLab and Private Packagist credentials, including CI job tokens, work as they are. |
| D9 | Publishing supports both one-repo-per-skill (standard Composer) and monorepos (`skillcask publish` builds a static Composer repository). | Many skills live in monorepos; GitLab's Composer registry accepts one package per project. |
| D10 | MIT OR Apache-2.0, no telemetry. | Usual Rust dual licence; nothing leaves the machine except registry requests. |
| D11 | GitHub repositories are a second source (`github = true`), resolved through the GitHub REST API; the lock format is unchanged. | Most public skills (the ones skills.sh lists) live in GitHub repositories without Composer metadata. Pinning the commit sha plus both hashes keeps D6. skills.sh itself is not used: its search and download APIs answered anonymously on 2026-10-26, but they are undocumented and could change or close without notice. |
| D12 | Repositories may carry every package inline in `packages.json` (Composer v1/Satis format) instead of `metadata-url`; `publish --inline` writes it, `--dist-url` places the zips. | Private monorepos can then be hosted on GitLab with no new infrastructure: `packages.json` lives in git and is read through the raw files API, zips go to the Generic Package Registry, whose file names cannot contain `/`. One file stays small for a few hundred skills. |
| D13 | `--global` manages personal skills: store `~/.agents/skills`, links in `~/.claude/skills` etc., manifest and lock in `~/.config/skillcask`; a skill name clash inside one scope is solved with `rename`, a clash across scopes is a warning. | Agents read personal skills from home and skills have no namespaces. The design is in `docs/specs/2026-10-20-global-and-aliases.md`. |
| D14 | `publish` records the tree hash of each new version in `extra.ai-agent-skill-tree`; without the published zip in `--out`, a version whose `shasum` differs counts as unchanged when its tree matches, and no zip is written for it. | CI that does not keep `dist/` must not fail on every published version when a `zip` or deflate update changes the bytes of the same tree. Downloading every old zip first would cost a request per version on each run. |
| D15 | A repository may set its own `min-release-age`, which overrides `policy.min-release-age` for packages resolved there; GitHub sources keep the policy value. | Internal skills are reviewed in merge requests and published after every merge; a project-wide `"0"` would also drop the cooldown for public sources. |
| D16 | A skill declares dependencies in a top-level `requires:` map of its `SKILL.md` frontmatter; they are resolved from the consumer's repositories (GitHub only with `policy.github-requires = true`), one version per package, and locked with `requires` in a `version = 2` lock. | Skills that call other skills break silently when one is missing. Composer `require` already holds `php` and plugins in existing packages and cannot name GitHub sources; reading the downloaded `SKILL.md` works for every source. The design is in `docs/specs/2026-10-20-skill-dependencies.md`. |
| D17 | A host no Composer source covers is asked from git's credential helper (`git credential fill`), on by default, off with `SKILLCASK_GIT_CREDENTIALS=0`; `skillcask auth set <host>` stores a token there. | Tokens then live in the macOS Keychain, the Windows Credential Manager or libsecret instead of a plain-text `auth.json`, with no new dependency: every developer machine has git and a helper. |
| D18 | Policy has layers: environment (`SKILLCASK_*`), keys a user `config.toml` lists in `enforce`, the project `[policy]`, the rest of `config.toml`, built-in defaults. `allow-sources` limits sources by name, `packagist`, `github` or URL prefix, at resolution and at install from the lock. `init` lists Packagist and GitHub in `[repositories]`; Packagist is always searched last. | Organisations that may only use their private registry need one rule for every project, CI and dependency, which a project cannot loosen unless allowed. Checking the lock too means a committed lock cannot bypass it. The design is in `docs/specs/2026-10-20-source-policy.md`. |
| D19 | Output has two modes: agent (`--agent`, `SKILLCASK_AGENT`, or detected from `AI_AGENT` / `CLAUDECODE`) prints terse, uncoloured, tab-separated lines and only problems; person gets colour in a terminal (off with `NO_COLOR`), hints on their own line and grouped `doctor` output. | Agents pay for padding and `ok` rows in tokens, people need to see at a glance what failed and what to run next. ANSI codes need no dependency. The design is in `docs/specs/2026-10-20-cli-output.md`. |
| D20 | Every HTTP request is a GET (or git's read-only `upload-pack` POST, D30) and is tried up to 3 times on a connection failure (I/O error or refused connection), 429 or 5xx: after 1 s and 2 s, or after `Retry-After` seconds up to 60 s. A longer `Retry-After`, an HTTP-date `Retry-After` (backoff instead), GitHub's spent quota (`x-ratelimit-remaining: 0`), timeouts, DNS and TLS errors and a body that breaks mid-read are not retried. | One 502 from a registry should not fail `install --frozen` in CI. GETs are idempotent, so retrying cannot repeat a side effect; `publish` only writes files. Waiting out a rate-limit window or a 300 s timeout again would stall CI longer than failing. |
| D21 | Composer `abandoned` (`true` or a replacement package) of a package's newest version is a warning in `add`, `update` (and `install` when it resolves) and `outdated`; `publish` writes it from a `deprecated:` frontmatter key (`true` or `vendor/name`). The replacement is printed only when it is a valid package name, so registry text cannot add escapes or lines. | Composer and Packagist already carry the flag, so authors of one-repo skills set it as for any package. The newest version decides because Composer marks the whole package; a retired monorepo skill gets it by publishing one more version, since published versions are immutable. A warning, not an error: the lock still pins reviewed content. |
| D22 | A `skills.lock` with a line starting with `<<<<<<<`, `=======` or `>>>>>>>` fails with a hint: keep either side, then `skillcask install`. | `install` re-resolves the manifest entries the kept side lacks, so no merge logic is needed; a TOML parse error alone does not say what to do. |
| D23 | `add`, `update` and `install` when it resolves warn about bidi controls (U+202A-202E, U+2066-2069, U+200E, U+200F, U+061C), zero-width characters (U+200B-200D, U+2060, U+FEFF) and Unicode tags (U+E0000-E007F) in the text (valid UTF-8) files of every skill they lock from a fresh download, with path, line and code point, five per file and a count of the rest. Not reported: a leading byte order mark and U+200D between two emoji. Installing from the lock, relocking the locked version and `update` resolving a dist with the sha256 already locked do not scan. | Such characters make an agent read other text than a reviewer sees (Trojan Source, ASCII smuggling in tags). A fixed list needs no network and no Unicode tables. Warnings, not errors: right-to-left and Indic text use some of them legitimately. The lock pins content that was already shown. |
| D24 | `skillcask validate [paths]` checks every SKILL.md under the paths (default `.`, found as `publish` finds them) against the Agent Skills specification: `name` 1-64 of `[a-z0-9-]`, no leading, trailing or double hyphen, equal to the directory name; `description` 1-1024 characters; `compatibility` at most 500; plus `requires:` and the file rules `publish` applies. It exits 1 on any error and warns about invisible Unicode as D23. `publish` warns about each SKILL.md it skips for lacking `name` or `version`. | Authors and monorepo CI find mistakes before publishing; a typo in the frontmatter used to publish nothing without a word. Install keeps accepting names such as `a--b` (`skill::valid_name`), so existing packages still install. |
| D25 | `outdated --strict` exits 1 when `update` would lock a newer version of a `skills.toml` entry: the same repository, policy, cooldown and constraint (with those of requirers added) as `update`; for a branch or commit entry, a different commit. Versions outside the constraint and dependencies do not count. | A scheduled CI job or bot needs a gate without parsing the table. Using `update`'s resolution means the gate fails only when `update` would change something; dependencies stay out, as in `outdated` (skill dependencies spec). |
| D26 | `info <target>` takes `vendor/name[@constraint]`, `github:owner/repo[@version-or-ref]` or a skill name. For a package it shows the locked version (else the newest `add` would take; `@` for another, cooldown not applied): skills with their descriptions, versions, description, license, `abandoned`, `requires`, and why it is locked. The dist is downloaded and verified (against the lock for the locked version) into the system temp dir; nothing in the project is written. For the locked version the skills (path and name) come from the lock, not from the registry's current metadata. Registry and `SKILL.md` text prints with control and D23 characters as `<U+XXXX>`. A name without `/` is an installed skill: the package that installs it (and its upstream name if renamed), then the `skills.toml` entry or the chain of requirers that brings it in; project and hand-written skills are named as such. | Skill names come from `SKILL.md` frontmatter, so only the archive tells which skills a package has; choosing `skills = [...]` should not need guessing. One command instead of `info` plus `why`: package names contain `/` and skill names cannot, so the argument says which question is asked. |
| D27 | `diff [pkg] [--to <constraint>]` prints a unified diff (Myers, 3 lines of context, no new dependency) of the skill files as installed, from the locked version to the one `update` would lock, or to the newest matching `--to` without the cooldown. Without a package: every `skills.toml` entry with a newer version. The old side comes from the store when its tree hash matches the lock, else from the locked dist (verified); the new dist is verified like `add`'s. Binary files (not UTF-8, or with NUL) print `Binary files differ`; exec bit changes print `old mode` / `new mode`. Control characters and the characters of D23 in lines and paths print as `<U+XXXX>`; changed files are scanned as in D23. A package new to the lock (a manifest entry not locked yet, or a dependency a new version adds) is diffed against nothing. A carriage return prints as `<U+000D>` unless both sides end every line with CRLF, so a line-end change is visible. `update --diff` prints the same diff for each package it changes or adds, before it writes the lock (a diff that fails changes nothing); it does not ask, so `diff` is the review step. Past 1000 edits in one file the diff replaces the whole file; a side over 1 MiB or 10,000 lines prints `Files differ (too large to show)`. Accepted: `info` and `diff` unpack into the system temp dir, which Ctrl-C leaves behind. | A skill is a prompt; reviewing its text before the update is the only real check, and the lock shows only hashes. Printing package text raw would let it drive the terminal or hide a change with bidi reordering. The edit cap keeps memory bounded (the Myers trace grows with the square of the edits); the size cap bounds time, since each Myers step walks the file. The OS cleans its temp dir; trapping signals would need a dependency. |
| D28 | While `config.toml` enforces `min-release-age`, it also binds the per-repository values of D15: a project may lengthen a repository's cooldown, never shorten it. Exceptions live in `config.toml` under `[policy.repository-min-release-age]`, keyed by `https://` URL prefix (longest match wins), and need `min-release-age` in `enforce`. The environment still lifts enforcement (D18). | Without it any project could write `min-release-age = "0"` on a repository and skip an organisation's cooldown. Keys are URL prefixes, as in `allow-sources`, because a repository name means whatever a project calls it. |
| D29 | An `[agents] targets` entry without `/` is an agent preset (`claude`, `kiro`, `junie`, `codex`, `copilot`, `cursor`, …) resolved per scope; agents that read `.agents/skills` get no link. `targets` comes from the manifest, else `config.toml` `[agents] targets`, else `["claude"]`; `init` stops writing it. Links in dropped target directories are removed. | 12 of 15 agents checked read the store, so users should name agents, not learn their directories, and set them once per machine. Paths need a `/` so a typo cannot create a directory. The design is in `docs/specs/2026-10-21-agent-targets.md`. |
| D30 | A skill entry may name a plain git repository, `{ git = "https://host/owner/repo.git", version | ref }` (`add git:<url>[@x]`, key = the last two URL parts), resolved like GitHub (D11): semver tags or a branch, tag or commit, pinned to the commit sha. skillcask speaks git's smart HTTP protocol (v0, stateless `upload-pack`, a read-only POST retried like a GET, D20) itself and fetches the commit at depth 1; every object is checked against its SHA-1 id from the pinned commit down, deltas included. The lock keeps D6's shape: `dist = { type = "git", url = <repository>, reference = <sha> }`, and `dist-sha256` is the sha256 of the sorted lines `<path>\0<mode>\0<sha256 of content>\n` (`644`, `755`, `120000` for a link) of the commit's files. Times are commit dates only; a branch whose head is within the cooldown falls back to the newest first-parent commit before the cutoff among 100, fetched without trees when the server supports `filter`, else it fails. Submodules are skipped; `requires:` and `info` take `git:` targets since D36. `flate2`, already built for `zip`, inflates the pack: no new crate. | GitLab, Bitbucket, Azure DevOps and self-hosted servers hold most private skills outside GitHub, and a Composer registry is one more thing to run. Running the git binary would bring in the user's configuration (global hooks via `core.hooksPath`, filters such as LFS, `core.fsmonitor`) and git's own record of clone vulnerabilities; reading the protocol directly keeps an install data-only, and it is small: packet lines, a pack, deltas. Hashing the file list instead of the transferred pack makes the lock independent of how a server packs or a future skillcask zips. git servers keep no push or release times, so the cooldown is as weak as for GitHub tags without a release: the pinned sha and the review of the lock remain the real check. |
| D31 | Next to D23, the same commands scan the same files for a fixed list of risky lines and warn with path and line, five per file and a count of the rest: download piped into a shell (`curl`/`wget`/`irm`/`iwr`/`Invoke-WebRequest`/`Invoke-RestMethod` and a `\|` into `sh`, `bash`, `zsh`, `dash`, `iex`, `Invoke-Expression`, `python`, `python3`, `perl`, `ruby`, `node`, also after `sudo`), base64 decoded and run (`base64 -d`, `--decode`, `b64decode`, `FromBase64String` with a pipe into a shell, `eval`, `exec(` or `iex`), SSH keys (`~/.ssh`, `$HOME/.ssh`, `id_rsa`, `id_ed25519`), `/etc/passwd` and `/etc/shadow`, and "ignore previous/prior instructions" phrasings; matched per line, lowercase, whitespace runs folded. `[policy] deny-patterns = true` (a D18 key, so `config.toml` can enforce it and `SKILLCASK_DENY_PATTERNS` override it) turns any match into exit 1 before anything is written; `info` and `diff` only warn. | Install-time scanners are common in other skill tools (`docs/research/2026-10-26-landscape.md` §4), and these patterns are how a skill turns an agent against its user. A fixed, documented list is predictable and needs no rules file or network; it catches the careless and the obvious, not a determined attacker, which is why review of `diff` stays the real check. Warnings by default because setup docs legitimately contain such lines; an organisation that prefers false positives to surprises can enforce the error. |
| D32 | `status`, `outdated`, `info`, `search` and `doctor` take `--json` and print one compact JSON document on one line of stdout instead of text, in both output modes (D19), with the same exit code; warnings, notes and errors stay on stderr as text. Keys: `status` {`ok`, `entries`: [{`package`, `version`, `skill`, `state`, `ok`, `adopt` (D38)}], `policy`: {key: {`value`, `from`}}, `targets`: {`entries`, `from`, `dirs`}}, every entry listed; `outdated` {`packages`: [{`package`, `locked`, `within`, `latest`, `note`}], `behind`}; `info` {`package`, `source` (`composer`, `github`, `git`), `repository`, `version`, `locked`, `description`, `license`, `abandoned` (`null`, `true` or the replacement), `versions` (all), `requires`, `skills`: [{`name`, `description`}], `why`}, or for a skill name {`skill`, `kind` (`package`, `project`, `hand-written`), …}; `search` {`results`: [{`name`, `description`}]}; `doctor` {`ok`, `passed`, `problems`, `fixed`, `warnings`}. Absent values are `null`, not `-`. Package text is escaped as in the terminal (`<U+XXXX>`, D26) and URLs are redacted. Keys are only added, never renamed or removed, within a major version. | Agents and CI read these commands; parsing tables breaks on every wording change and costs tokens. One document per command rather than one object per line: the outputs are small, have a header (`ok`, `policy`) next to their rows, and `jq` reads either. Escaping keeps the guarantee of D26 that package text cannot reorder what a reader sees, which matters as much to an agent reading JSON. |
| D33 | `action.yml` at the repository root is a composite GitHub Action: it downloads `skillcask-<target>.<ext>` of release `v<version>` for the runner (Linux x64 musl, Linux arm64, macOS arm64 and x64, Windows x64), checks the sha256 the release lists and, unless `verify-attestation: false`, the build provenance attestation with `gh attestation verify`, adds the binary to `PATH` and runs `skillcask <args>` (default `install --frozen`) in `working-directory`. `version` defaults to the tag the action is used at; at a branch or sha it must be given. It uses no other action; `args` reaches the shell only through the environment, split on whitespace. | CI is where `install --frozen` matters, and every other skill tool with a lock ships an action. A composite action needs no build of its own and no third-party action to pin. The sha256 alone only guards the download, since it comes from the same release; the attestation ties the archive to this repository's release workflow. Taking the version from the tag keeps the binary and the action on one pinned release. |
| D34 | `skillcask audit` reads every skill on disk: locked ones and hand-written ones in the store, and the project skills. For each it lists what the text reaches: `commands` (first words of every command, split on `\|`, `&&`, `\|\|` and `;`, in Markdown code blocks tagged `bash`, `sh`, `shell`, `zsh`, `fish`, `console`, `terminal`, `powershell`, `pwsh`, `ps1` or `cmd`, with prompts, `sudo`, shell keywords and leading `VAR=` assignments skipped, and comments, continuation lines, heredoc bodies and words that cannot name a program (capitals outside PowerShell blocks, `)`, `:`, `/`) left out), `network` (hosts of `http(s)://` URLs), `paths` (tokens starting with `~/`, `$HOME/`, `%USERPROFILE%`, `C:\` or `/etc`, `/usr`, `/var`, `/opt`, `/tmp`, `/Users`, `/home`, `/root`), `env` (upper-case `$NAME`, `${NAME}`, `$env:NAME`, `x.env.NAME`) and `scripts` (executable files and `sh`, `bash`, `zsh`, `ps1`, `cmd`, `bat`, `py`, `js`, `mjs`, `rb`, `pl`). Findings, with rule ids that are part of the output: `modified` (a locked skill not installed or not matching its tree hash, level error), `risky-pattern` (D31) and `invisible-character` (D23), both warnings, every occurrence. Exit 1 on any finding. `--json` (D32 rules) prints {`ok`, `skills`: [{`skill`, `kind` (`package`, `hand-written`, `project`), `package`, `version`, `path`, `findings`: [{`rule`, `path`, `line`, `message`}], `commands`, `network`, `paths`, `env`, `scripts`}]}; `--sarif` a SARIF 2.1.0 log with one result per finding, paths relative to the project root (the home directory with `--global`). | Install-time warnings show only new content, once; a reviewer and CI also need to see what is installed now, including hand-written skills nobody locked, and what each skill asks an agent to touch (as HarnessKit's permission view does). Reading the text keeps it data-only and offline; it is a list for a reviewer, not a sandbox, so reach never fails the command. SARIF is what GitHub and GitLab code scanning read, so findings land in the merge request without a converter. |
| D36 | `requires:` keys and `info` take `git:https://host/owner/repo.git` (`requires:` also `#skill` for one skill), named and resolved as a D30 entry; such a dependency needs `github-requires = true` like a GitHub one, and two requirers (or the manifest entry) naming one package from different GitHub or git URLs is a conflict. `outdated` notes, and warns about, a locked GitHub or git tag that now names another commit (`tag v1.2.0 moved from <sha> to <sha>`); `update` warns whenever it relocks the same version with other content, for any source. Branches are not checked: a branch is expected to move. | Teams that host skills on GitLab or a self-hosted server could depend on them only through a Composer registry. A moved tag is how a compromised or careless maintainer swaps content under a version a reviewer already approved (rulesync detects it for locked commits); `install` still installs the locked commit, so the danger is the next `update`, which these warnings make visible before anyone accepts it. |
| D37 | When a GitHub or git repository (skills discovered, D11, D30) has two skill directories with the same name, the one with fewer path components wins and `add`/`update` warn (`skill "x" is in skills/x and plugins/p/skills/x; using skills/x`) when the skill is selected; equal depth still fails. A Composer package declares its paths, so a duplicate there stays an error. | Repositories that ship a plugin bundle next to their skills (`skills/x` and `plugins/<p>/skills/x`, as in public skill collections) could not be installed at all, not even one other skill from them. The top-level copy is the one such repositories present as the skill, and the one `npx skills` installs; the lock records the chosen path, so `install` never has to choose again. |
| D38 | Global scope only: `status` lists every skill directory in the store or a target that is neither locked nor in the managed list as `not managed`, a healthy state (exit code unchanged); `status --json` entries gain `adopt`, the `github:owner/repo/skill` source recorded for that name in `~/.agents/.skill-lock.json` (the lock of `npx skills`), else `null`. `add --adopt` (refused without `--global`) moves what stands at the new package's skill names and is not skillcask's (the store dir, and target entries other than links into the store) to `<config>/adopted/<unix time>/<path>` before installing; a name another locked package provides is left to the usual conflict. | Personal skills often come from other installers first; an app or user that sees an empty list concludes skillcask is broken, and the only way in was to delete the copy and `add` again. Moving instead of deleting keeps local edits recoverable; the config directory is outside every agent's skill directories, so the old copy is not loaded as a second skill. Project scope keeps hand-written skills (`docs/specs/2026-10-20-global-and-aliases.md`) and has no adopt: there a name clash is a repository decision, made with `rename`. |
| D39 | `diff --from <file> [pkg]` (not with `--to`) compares the lock in `<file>` (`-`: stdin) with `skills.lock`: for each package whose `dist-sha256` or skills differ, the D27 diff from the old entry (store or verified old dist) to the new one, after the new dist passes the checks `install` makes (`dist-sha256`, each skill's `tree-sha256`, `[policy]` on its repository); a package only in the old lock prints `<name> <version> (removed)`. Nothing is installed or written. skillcask reads a file, never a git revision. | A reviewer of a lock change sees new versions and hashes, not the prompt text they bring (the drawback raised against lockfiles in review). `diff` showed only what the next `update` would do, before the lock changed. Taking a file keeps skillcask free of the git binary (as D30), and every CI already has the target branch at hand; the verification means the diff is what `install` would place, or the same error. |

## Project files

```
skills.toml                  # manifest, committed
skills.lock                  # lock, committed, generated
.agents/skills/<name>/       # installed skill (managed: gitignored; hand-written: committed)
.claude/skills/<name>  -> ../../.agents/skills/<name>
.junie/skills/<name>   -> ../../.agents/skills/<name>
.skills/<name>/              # project skill, committed; .agents/skills/<name> links to it
.gitignore                   # managed block
```

### `skills.toml`

```toml
[repositories]
# packagist = { type = "composer", url = "https://repo.packagist.org" }  # implicit default
acme = { type = "composer", url = "https://git.example.com/api/v4/group/42/-/packages/composer/packages.json" }
# own = { url = "…", min-release-age = "0" }   # overrides policy.min-release-age here (D15)

[skills]
"netresearch/agent-jira-skill" = "^2.0"
"acme/agents-md" = { version = "^1.0", repository = "acme" }
"acme/review" = { version = "1.4.2", repository = "acme", skills = ["review"] }

[agents]
targets = ["claude"]                            # default (D29); .agents/skills is always the store
local = ".skills"                                 # default; project skills

[policy]
min-release-age = "3d"     # default; "0" disables
allow-ranges = true        # false: every version must be exact (x.y.z)
packagist = true           # false: drop the implicit Packagist repository
```

- A skill entry without `repository` is looked up in declared repositories in order, then
  Packagist. The repository that served it is written to the lock. Once locked, `install`, `update` and `add` look
  for it only in that repository; if it is gone from there, they fail rather than take a package
  with the same name from another repository. Setting `repository` moves it on purpose.
- `skills = [...]` selects skills from a package that ships several; default: all.
- `policy.allow-ranges = false` is for organisations whose standard forbids ranges even with a
  lock; `add` then writes the resolved exact version.
- GitHub entries: `{ github = true, version = "^1.3" }` resolves over version tags;
  `{ github = true, ref = "main" }` follows a branch, tag or commit; neither means the default
  branch (`HEAD`). The key is `owner/repo`, lowercase. `repository` cannot be combined with
  `github`. With `allow-ranges = false`, `ref` must be a full commit sha.

### `skills.lock`

```toml
version = 1

[[package]]
name = "acme/agents-md"
constraint = "^1.0"
version = "1.0.2"
repository = "https://git.example.com/api/v4/group/42/-/packages/composer/packages.json"
dist = { type = "zip", url = "https://…/agents-md-1.0.2.zip", reference = "9f2c1e…" }
dist-sha256 = "…"
released = 2026-10-01T09:12:00Z
skills = [{ name = "agents-md", path = "", tree-sha256 = "…" }]
```

- `reference`: `dist.reference`, else `source.reference` from the metadata (a commit sha for
  VCS-backed packages).
- `dist-sha256`: computed by skillcask at lock time. Composer's `dist.shasum` is used only as an
  extra check when present (it is empty for GitHub zipballs).
- `tree-sha256`: hash of the installed skill directory. Definition: for every regular file, sorted
  by relative path with `/` separators, the line `<path>\0<mode>\0<sha256 of content>\n`, where
  mode is `644` or `755`; the hash of the concatenation. No symlink is ever written: a
  relative symlink to a regular file inside the same skill (`CLAUDE.md -> AGENTS.md`) is installed
  and hashed as a copy of that file; any other symlink inside a skill, devices and empty
  directories are rejected at install. Symlinks outside the installed skill directories are
  ignored.
- `ref` (GitHub entries only): `true` when `constraint` is a branch, tag or commit (`ref =` in the
  manifest), `false` when it is a version constraint over tags.
- `selected`: the entry's `skills = [...]`, sorted; absent when the entry installs all skills.
- `ref` and `selected` are written only when they apply, so other entries render as before.
  Locks written before these keys existed still parse and install: an absent `selected` means
  all skills unless the manifest entry has `skills = [...]` (then the locked skill names are
  compared, as before), and an absent `ref` is not compared. A non-frozen `install` adds the
  missing keys; `--frozen` never fails only because they are missing.
- Parsing rejects (exit 1, `skills.lock: invalid …`) a hash that is not 64 lowercase hex digits,
  a dist URL that is not `https://`, a dist type other than `zip`, a package listed twice, and a
  `from` equal to the skill's `name`.
- Written atomically: a temp file in the same directory, then a rename (`skills.toml` too).
- Entries sorted by `name`; no timestamps other than `released`, so parallel branches merge.

## Package format

A skill package is a Composer package with `"type": "ai-agent-skill"`, or any package with
`extra.ai-agent-skill`:

```json
{ "name": "acme/agents-md", "type": "ai-agent-skill", "extra": { "ai-agent-skill": "SKILL.md" } }
```

`extra.ai-agent-skill` is a path to a `SKILL.md` (the skill is its directory) or a list of such
paths for packages with several skills. Missing: `SKILL.md` at the package root. The skill name
is the frontmatter `name`; it must match `[a-z0-9][a-z0-9-]*` and is the directory name under
`.agents/skills/`. Two packages providing the same skill name is an error naming both.

## Resolution

1. Read `packages.json` of each repository (a URL ending in `.json` or carrying a query string is
   used as given, otherwise `/packages.json` is appended). Take the package from the inline
   `packages` map when it is there (Composer v1: version → metadata), else follow `metadata-url`
   (`/p2/%package%.json`). Expand Composer's minified format (`"minified": "composer/2.0"`: each version inherits
   fields from the previous one; `"__unset"` removes a field).
2. Keep versions whose type is `ai-agent-skill` or that carry `extra.ai-agent-skill`.
3. Stability: stable only (`version_normalized` without a stability suffix) unless the
   constraint names one (`1.0.0-beta2`, `@beta`). `dev-*` branches are never resolved.
4. Constraints follow Composer semantics, not npm's: `^1.2` = `>=1.2.0 <2.0.0`, `^0.3` =
   `>=0.3.0 <0.4.0`, `~1.2` = `>=1.2 <2.0`, `~1.2.3` = `>=1.2.3 <1.3.0`, `1.2.*`, `>=`, `<`, `!=`,
   AND by space or comma, OR by `||`.
5. Cooldown: drop versions whose `time` is newer than `now - min-release-age`. A version without
   `time` is kept with a warning (GitLab metadata may omit it). If the cooldown removes every
   match, the error names the newest version and when it becomes eligible.
6. Pick the highest remaining version.

### GitHub sources

1. `version`: list tags (`GET /repos/{o}/{r}/tags`, up to 1,000), keep those that parse as
   versions, apply the constraint. Release time is the tag's commit date, or the publication
   time of its GitHub release when that is later (`GET /repos/{o}/{r}/releases`, first 100),
   fetched newest first until one passes the cooldown. Tags are read once per run.
2. `ref`: `GET /repos/{o}/{r}/commits/{ref}`. For a branch (`HEAD` is the default branch), the
   Activity API (`GET /repos/{o}/{r}/activity?ref={branch}`, first 100) gives push times: the
   eligible commit is the head after the newest push before the cutoff, or the head before the
   oldest listed push when all of them are newer and fewer than 100 are listed. A tag, or a
   branch without listed activity, falls back to commit dates: if the commit is newer than the
   cooldown and the ref is not a sha, take the newest commit on the ref before the cutoff
   (`commits?sha={ref}&until={cutoff}`) and say so.
3. Lock: `repository` = `<api>/repos/{o}/{r}`, `dist.url` = `<api>/repos/{o}/{r}/zipball/{sha}`,
   `reference` = the sha, `version` = the tag, or the first 12 characters of the sha for a ref.
4. Skills: every `SKILL.md` in the archive that is not inside another skill. Name: frontmatter
   `name` if valid, else the directory name (the repository name for a root `SKILL.md`); neither
   valid skips it with a warning.

Commit dates are set by the committer, so where they are the only time (a tag without a release, a
ref without listed pushes, a pinned sha) the cooldown is weaker than with registry release times;
the pinned sha and hashes still make `install` reproduce exactly what was reviewed. GitHub
zipballs are not guaranteed byte-stable; if GitHub regenerates one, `install` stops with a hash
mismatch (exit 4) rather than installing unverified content.

### Plain git sources

As GitHub sources, with these differences (D30): refs come from
`GET <url>/info/refs?service=git-upload-pack`, a commit from `POST <url>/git-upload-pack`
(`want <sha>`, `deepen 1`); tags peel to their commit; `HEAD` is the default branch. The lock's
`repository` and `dist.url` are the repository URL, `reference` the sha, `version` the tag or the
first 12 characters of the sha. `allow-sources` matches the URL by prefix.

## Commands

| Command | Behaviour |
|---|---|
| `init` | Create `skills.toml` with defaults. |
| `add github:<owner/repo>[/skill][@version-or-ref]` | GitHub entry; `/skill` adds to `skills = [...]`. `@x` is a version constraint when it parses as one, else a ref. Without `@`: version tags if the repository has any (`^<major.minor>`), else the default branch. |
| `add git:<https-url>[@version-or-ref]` | Plain git entry named after the URL's last two parts (D30); `@x` as for GitHub. |
| `add <vendor/name>[@constraint] [--repository r]` | Resolve first (typo or no match leaves files untouched), write manifest and lock, install. No constraint: the existing entry's constraint, else `^<major.minor>` of the resolved version, or the exact `x.y.z` with `allow-ranges = false`. |
| `remove <vendor/name>…` | Drop from manifest and lock; remove installed directories, links and gitignore lines. |
| `install [--frozen]` | Install exactly the lock: download dist, verify `dist-sha256`, unpack to a temp dir, verify every `tree-sha256`, move into place, link, rewrite the gitignore block. Entries in the manifest that do not match the lock (missing, or a changed constraint, repository, GitHub mode, `skills` selection or `rename`) are resolved and locked; with `--frozen` (implied when `CI` is set) that is exit 1 instead. When only `skills` or `rename` changed, or the locked version still satisfies a changed constraint, the locked version is kept. Already-installed skills whose tree hash matches are skipped. |
| `update [vendor/name…] [--diff]` | Re-resolve within constraints (cooldown applies), rewrite the lock, install; `--diff` prints each changed or added package's diff before writing the lock, without asking (D27). Entries not locked yet are resolved too; other drifted entries get a warning. |
| `outdated [--strict]` | Per package: locked, newest within constraint, newest overall, eligible date under cooldown. `--strict`: exit 1 when `update` would lock a newer version (D25). |
| `diff [pkg] [--to <constraint>]` | Unified diff of skill files from the locked version to the one `update` would lock (D27). |
| `info <vendor/name[@c]\|github:owner/repo[@v]\|skill>` | Skills, versions and metadata of a package, or which package and entry install a skill (D26). |
| `status` | Manifest vs lock (every reason `install --frozen` checks, and a skill name provided by two packages) vs installed (hash) per skill. Exit 1 on any mismatch. |
| `audit [--json\|--sarif]` | What installed and project skills reach, and modified files, risky lines and invisible characters (D34). Exit 1 on any finding. |
| `doctor [--fix]` | Broken or committed managed links, stale gitignore block, modified installed skills (tree hash). A person also sees each check that passed. `--fix` repairs without downloading. |
| `search <query>` | Packagist search API filtered by `type=ai-agent-skill`; for other repositories, a substring match over the names in `available-packages`, inline `packages` or `provider-includes` (GitLab), then the metadata of up to 30 matches to keep skill packages and show their description. A failing repository is a warning unless all fail. |
| `<other>` | Runs `skillcask-<other>` from `PATH` with the remaining arguments and exits with its code (git/cargo-style plugins). Only executables the user installed; packages never provide them. Migrations from other manifest formats live in plugins, not in the core. |
| `publish` | See Publishing. |

Exit codes: 0 ok; 1 manifest/lock/status problems or drift under `--frozen`; 2 authentication;
3 network or HTTP error; 4 hash mismatch; 5 IO or archive error.

## Installing and linking

- Store: `.agents/skills/<name>/`, replaced atomically (unpack to a sibling temp dir, verify,
  rename). Temp dirs carry the pid of their run, which holds a lock on
  `.agents/skills/.skillcask-run-<pid>` while it lives; `install` removes the ones whose run is
  gone (without a run lock, from older versions: those older than an hour).
- Each target in `agents.targets` gets `<target>/<name>` → relative path to the store.
- Managed skills (present in the lock) and their links are listed in a marked `.gitignore` block,
  regenerated on every `install`, `update`, `remove`. A managed link found in the git index is
  removed from it (`git rm --cached`), never from the working tree.
- Hand-written skills: any directory under `.agents/skills/` with a `SKILL.md` and no lock entry
  is linked into the targets too, and those links are committed (their target is tracked, so they
  resolve in every clone). A name that is both hand-written and locked is an error.
- Project skills: every `<local>/<name>/SKILL.md` (`[agents] local`, default `.skills`) gets
  `.agents/skills/<name>` → `../../<local>/<name>`, then the usual target links. All of them are
  committed. When the project skill is deleted, its links are removed on the next `install`. A
  name that is both a project skill and locked is an error.
- A name clash inside the project (two packages, a project skill, a foreign directory) is an
  error that names the `rename = { … }` fix; in a terminal `add`, `install` and `update` offer it.
  A personal skill with the same name (`~/.claude/skills/<name>`) is a warning. See D13.
- Windows without symlink permission: copy instead of link, and list the copies in the managed
  block.

## Authentication

Sources, first match per host: `COMPOSER_AUTH` (JSON), `./auth.json`, `$COMPOSER_HOME/auth.json`
(default `~/.composer/auth.json` or `~/.config/composer/auth.json`). Supported keys:
`http-basic`, `bearer`, `gitlab-token`, `gitlab-oauth`, `github-oauth` (a `github.com` token is
also used for `api.github.com`). `GITHUB_TOKEN` or `GH_TOKEN` is the last fallback for the GitHub
API host (`SKILLCASK_GITHUB_API`, default `https://api.github.com`). Then git's credential helper
(D17): `git credential fill` once per remaining host, never interactive (no terminal prompt, no
askpass, `GCM_INTERACTIVE=never`), off with `SKILLCASK_GIT_CREDENTIALS=0`. The username picks the
header: `PRIVATE-TOKEN` the GitLab header, `oauth2` a Bearer token, any other HTTP Basic.
`skillcask auth set <host> [--username U]` stores a token (asked by git without echo, or read from
a pipe) and `auth remove` deletes only that username's entry. A GitLab CI job reads the registry with
`http-basic` user `gitlab-ci-token`, password `$CI_JOB_TOKEN`. Tokens are never printed, including
in `--verbose` URLs.

## Security

- HTTPS only; `http://` repositories and dist URLs are rejected. TLS through the platform
  verifier (system trust store), so corporate CAs work without flags; no option to disable
  verification.
- Archives: reject absolute paths, `..`, symlinks leaving their skill, hard links and devices; limits on download
  size (50 MiB), unpacked size (100 MiB) and file count (5,000), overridable per command.
- Archive names must work on every OS: no Windows-reserved names (`CON`, `PRN`, `AUX`, `NUL`,
  `COM1`-`COM9`, `LPT1`-`LPT9`, also with an extension), no trailing dot or space, no
  `<>:"|?*\` or control characters, and no two paths that are one name on a case-insensitive
  or Unicode-normalising file system (`README.md` and `readme.md`, `café` composed and
  decomposed). Such entries are not extracted. A selected skill that contains one fails with
  the same error on every OS; outside the selected skills they are skipped, so a stray file in
  a repository does not block its skills. Duplicate entries and mismatched zip headers fail the
  whole archive, and the limits count every entry.
- No package code runs at any point.
- Release artefacts: checksums and build provenance attestations; `skillcask --version` prints
  the commit.

## Publishing

**One repository per skill**: a `composer.json` with the convention above and semver tags.
Packagist reads public repositories; GitLab publishes a tag to its Composer registry
(`POST /projects/:id/packages/composer`). skillcask has no part in it.

**Monorepo**: `skillcask publish --vendor acme --base-url <url> --out <dir> [paths…]` finds
every `SKILL.md` with frontmatter `name` and `version`, and writes a static Composer repository:

```
<dir>/packages.json            # metadata-url: <base-url>/p2/%package%.json, available-packages
<dir>/p2/acme/<name>.json      # all published versions, not minified
<dir>/dist/acme/<name>/<version>.zip
```

- Package name: frontmatter `package:` when set, else `<vendor>/<name>`. The directory a skill sits
  in plays no part, so nested folders (`skills/team/lang/<name>`) give `<vendor>/<name>` too. One
  package comes from one directory: two `SKILL.md` files with the same package name are an error,
  fixed with `package:` in one of them.
- Zips are deterministic (sorted entries, fixed mtime, fixed permissions), so the same tree gives
  the same `shasum`, which `publish` writes into the metadata.
- Versions are immutable: `--out` may hold a previous run; an existing version with a different
  hash is an error, an identical one is kept. Without its zip in `--out`, a version is identical
  when its tree matches `extra.ai-agent-skill-tree` (D14); versions published by an older skillcask get
  that key on the first run whose zip still matches.
- `time` is the publish time of the version, set once, truncated to the second.
- `--dist-url <template>` sets the zip URL of new versions with `{vendor}`, `{name}` and
  `{version}`; default `<base-url>/dist/{vendor}/{name}/{version}.zip`. Zips are written to
  `dist/` either way; uploading them to the template URL is the publisher's job.
- `--inline` (D12) writes all packages into `packages.json` as `packages.<name>.<version>` and no
  `p2/`; `--base-url` is then optional when `--dist-url` is given. Earlier versions are read from
  either layout, so switching keeps them.

**Private hosting on GitLab** (monorepo): CI runs `publish --inline` with a Generic Package
Registry `--dist-url` (`.../packages/generic/{vendor}-{name}/{version}/{name}-{version}.zip`),
uploads new zips, and commits `packages.json` to the repository, which also keeps the state the
next run needs. Clients use the raw files API URL
(`.../repository/files/<path-encoded>/raw?ref=<branch>`) as the repository `url`; a
`gitlab-token` (sent as `PRIVATE-TOKEN`) for the host covers both requests.

## Testing

- Unit: constraint parser (table of Composer's own test cases for `^`, `~`, `*`, stability),
  minified metadata expansion, tree hash, lock round-trip, gitignore block rewrite.
- Integration: a local HTTPS server (test CA) serving a fixture Composer repository, covering
  install, frozen drift, hash mismatch (exit 4), cooldown, auth (`http-basic`, `bearer`),
  archive attacks (zip slip, symlink, size limit), collisions, Windows copy mode (on the Windows
  runner).
- `publish` → `install` round trip against the generated static repository, in both layouts.
- End to end against Packagist with `netresearch/agent-jira-skill`, `#[ignore]` by default.

## Distribution

GitHub repository `skillcask`, also a GitHub Action (`action.yml`, D33); releases via `cargo-dist` for macOS (arm64, x86_64), Linux
(x86_64, arm64, musl) and Windows; Homebrew tap; `cargo install skillcask`; checksums and GitHub
artefact attestations. The crate name `skillcask` was free on crates.io on 2026-10-19.

## Acceptance

- `skillcask add netresearch/agent-jira-skill` in an empty git repository creates `skills.toml`,
  `skills.lock`, `.agents/skills/<name>/`, links in `.claude/skills` and `.junie/skills`, and a
  gitignore block; a fresh clone plus `skillcask install --frozen` reproduces the same tree hash.
- Changing one byte of an installed skill makes `status` exit 1; tampering with the served zip
  makes `install` exit 4.
- With `CI=true`, a manifest entry missing from the lock makes `install` exit 1 without writing
  anything.
- A version published 1 hour ago is not selected by `add` with the default policy, and the error
  says when it becomes eligible.
- `publish` on a monorepo with three skills produces a repository that `install` consumes, and a
  second `publish` of unchanged skills changes no file.

## Open questions

1. ~~Private static repository hosting for monorepos.~~ Decided in D12: inline `packages.json`
   in git, zips in the Generic Package Registry. Rejected: GitLab's Composer registry (one package
   per project), GitLab Pages (cookie auth, a CLI cannot authenticate), `p2/` in the Generic
   Package Registry (no `/` in file names), an object store behind a token proxy (new
   infrastructure).
2. ~~Whether `search` should query several Composer repositories at once or only Packagist.~~ It
   queries all of them; see `search` above.
