# Fixtures

One directory per CLI release, holding what that release printed. Files are byte-for-byte what the binary
wrote (one line per document), so `diff 0.9.1 0.10.0` shows exactly what upstream added.

## 0.9.1

Captured 2026-10-27 from `skillcask 0.9.1 (1afcd7c81d2e)` in a throwaway project: `init`, a project skill
`.skills/notes/SKILL.md` with a `curl … | sh` line, `~/.ssh` and `$HOME`, then `add netresearch/agent-jira-skill`
(Packagist, abandoned, two skills). Never captured with `-g`.

| File | Command | Exit |
|---|---|---|
| `status.empty.json` | `status --json` right after `init` | 0 |
| `status.json` | `status --json` with the package and the project skill | 0 |
| `status.problem.json` | same after editing an installed SKILL.md (`modified`) | 1 |
| `status.missing.json` | same after deleting an installed skill (`not installed`) | 1 |
| `status.noproject.stderr` | `status --json` outside a project (stdout empty) | 1 |
| `outdated.empty.json` | `outdated --json` after `init` | 0 |
| `outdated.json` | `outdated --json` with the package locked at its latest | 0 |
| `info.package.json` | `info --json -- netresearch/agent-jira-skill` | 0 |
| `info.skill.package.json` | `info --json -- jira-syntax` | 0 |
| `info.skill.project.json` | `info --json -- notes` | 0 |
| `search.json` | `search --json -- jira` with skills.sh undecided | 0 |
| `doctor.empty.json` | `doctor --json` after `init` (same as healthy) | 0 |
| `doctor.problem.json` | `doctor --json` after deleting an installed skill | 1 |
| `audit.empty.json` | `audit --json` after `init` | 0 |
| `audit.json` | `audit --json` with the project skill's risky lines | 1 |
| `audit.problem.json` | same after editing an installed SKILL.md (`modified` finding) | 1 |
| `projects.json` | `projects --json -- <dir>` | 0 |
| `diff.up-to-date.txt` | `diff` with nothing newer (text; stderr merged) | 0 |

## config-0.9.4

Captured 2026-10-28 from `skillcask 0.9.4` built from this repository, with `HOME` a fresh temporary directory and
nothing else in the environment, so `-g` only ever touched that directory's `config.toml`. Not a `<version>/`
directory: the per-release tests would expect every document above in it. One edit: the temporary directory is
replaced by `/Users/me` in every file.

| File | Command (all `-g`) | Exit |
|---|---|---|
| `config.empty.json` | `config --json` with no config.toml | 0 |
| `config.set.json` | `config --json` after setting `min-release-age 3d`, `allow-ranges true`, `allow-sources packagist https://user:tok@repo.example/p?x=1`, `enforce min-release-age allow-ranges`, `agents.targets claude codex`, `search.skills-sh false` | 0 |
| `config.refused-unset-enforced.stderr` | `config --unset -- policy.min-release-age` while `enforce` lists it | 1 |
| `config.refused-source.stderr` | `config -- policy.allow-sources http://user:tok@bad.example` (quoted as typed) | 1 |
| `config.refused-age.stderr` | `config -- policy.min-release-age soon` | 1 |
| `config.unknown-key.stderr` | `config -- policy.nope 1` (error and hint) | 1 |
| `config.environment.json`, `.stderr` | `config --json` with `SKILLCASK_ALLOW_RANGES=false` | 0 |
| `config.broken.stderr` | `config --json` with `nonsense = 1` in config.toml | 1 |

Shapes a real run cannot produce yet (dependency `via` labels, drift sentences, planned keys) live inline in the
tests as `synthetic` strings, next to the assertion that needs them.
