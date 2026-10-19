# skillcask

A lockfile-first package manager for AI agent skills: directories with a `SKILL.md`, read by
Claude Code, Codex, Junie and others.

skillcask installs skills the way Cargo or Composer install libraries. It reads a manifest with
version constraints and commits a lock with content hashes. In CI it does frozen installs that
fail on drift, and it links every skill into each agent's skill directory. It ships as a single
static binary with no runtime, so it works in a repository in any language.

Skills are distributed through the Composer repository protocol. Packagist serves public skills;
GitLab's Composer registry, Satis, Private Packagist or the static repository built by
`skillcask publish` serve private ones. skillcask does not need PHP or Composer.

## Install

```sh
brew install puniserv/tap/skillcask   # macOS, Linux
npm install -g skillcask              # or: bun add -g skillcask
npx skillcask install --frozen        # or: bunx skillcask …, no global install
cargo install skillcask
```

The npm package is a thin wrapper that downloads the release binary for your platform from
GitHub. It does not check a checksum itself; where that matters, install the binary directly
and verify it.

Prebuilt binaries for macOS, Linux and Windows are on the
[releases page](https://github.com/puniserv/skillcask/releases), with sha256 checksums and GitHub
build provenance attestations (`gh attestation verify <file> -R puniserv/skillcask`).

## Use

```sh
skillcask add netresearch/agent-jira-skill   # resolve, write skills.toml + skills.lock, install
skillcask install --frozen                   # CI: install exactly the lock or exit non-zero
skillcask status                             # manifest vs lock vs installed files
```

`add` creates:

```
skills.toml                  # manifest, commit it
skills.lock                  # lock, commit it
.agents/skills/<name>/       # installed skill (gitignored)
.claude/skills/<name>  -> ../../.agents/skills/<name>
.junie/skills/<name>   -> ../../.agents/skills/<name>
.gitignore                   # managed block
```

Project skills live in `.skills/<name>/SKILL.md` (`[agents] local`). skillcask links each one
into the store (`.agents/skills/<name> -> ../../.skills/<name>`) and from there into every agent
directory. These links are committed, so they work in every clone. A directory written by hand
straight into `.agents/skills/` is linked the same way. A project skill with the same name as a
locked one is an error.

### skills.toml

```toml
[repositories]
# Packagist is the implicit last repository.
acme = { type = "composer", url = "https://git.example.com/api/v4/group/42/-/packages/composer/packages.json" }

[skills]
"netresearch/agent-jira-skill" = "^3.34"
"acme/agents-md" = { version = "^1.0", repository = "acme" }
"acme/review" = { version = "1.4.2", repository = "acme", skills = ["review"] }

[agents]
targets = [".claude/skills", ".junie/skills"]
local = ".skills"        # project skills

[policy]
min-release-age = "3d"   # cooldown for add/update; "0" disables
allow-ranges = true      # false: every version must be exact
packagist = true         # false: drop the implicit Packagist repository
```

Constraints follow Composer semantics: `^0.3` means `>=0.3.0 <0.4.0`, `~1.2` means
`>=1.2 <2.0`, and pre-releases are only selected when the constraint names a stability
(`^1.0@beta`).

### Commands

| Command | |
|---|---|
| `init` | Create `skills.toml`. |
| `add <vendor/name>[@constraint] [--repository r]` | Resolve, lock and install. |
| `remove <vendor/name>…` | Drop from manifest and lock; delete files, links and gitignore lines. |
| `install [--frozen]` | Install the lock. `--frozen` (implied by `CI`) fails when the lock is out of date. |
| `update [vendor/name…]` | Re-resolve within constraints. |
| `outdated` | Newer versions, and when cooled-down ones become eligible. |
| `status` | Exit 1 when manifest, lock or installed files disagree. |
| `doctor [--fix]` | Broken or committed links, stale gitignore block, modified skills. |
| `search <query>` | Packagist (`type=ai-agent-skill`) and listed private packages. |
| `publish --vendor v --base-url URL --out DIR [paths…]` | Build a static Composer repository from a monorepo. |
| `<other>` | Runs `skillcask-<other>` from `PATH`, like git and cargo plugins. |

Exit codes: 0 ok, 1 manifest/lock/status problems, 2 authentication, 3 network, 4 hash mismatch,
5 IO or archive error.

## Security

- The lock pins the version, the commit reference, the sha256 of the downloaded archive and
  the tree hash of every installed skill. `install` verifies both hashes, so what gets installed
  is what was reviewed.
- HTTPS only, verified against the system trust store, so corporate CAs work. Verification
  cannot be turned off; `SKILLCASK_CA_FILE` replaces the trust store with a PEM bundle.
- Archives with absolute paths, `..`, devices or symlinks that leave their skill are rejected.
  No symlink is ever written from a package. Size and file count are capped (`--max-download`,
  `--max-unpacked`, `--max-files`).
- No package code runs, ever. No telemetry.
- Credentials come from Composer's `auth.json` / `COMPOSER_AUTH` (`http-basic`, `bearer`,
  `gitlab-token`, `gitlab-oauth`) and are never printed. In GitLab CI use `http-basic` with the
  user `gitlab-ci-token` and the password `$CI_JOB_TOKEN`.

## Publishing skills

**One repository per skill:** a `composer.json` with `"type": "ai-agent-skill"` (the
[netresearch convention](https://github.com/netresearch/composer-agent-skill-plugin)) and semver
tags. Packagist or GitLab's Composer registry picks up the tags; skillcask plays no part.

**Monorepo:** give each `SKILL.md` a `version` in its frontmatter and run

```sh
skillcask publish --vendor acme --base-url https://skills.example.com --out public skills/
```

This writes `packages.json`, `p2/acme/<name>.json` and deterministic zips under `dist/`. Published
versions are immutable, and re-running on unchanged skills changes no file. Serve the directory
over HTTPS.

## Design

See [docs/spec.md](docs/spec.md).

## License

MIT OR Apache-2.0.
