# Spec: global scope, install aliases, shadow warnings

Date: 2026-10-20. Status: implemented.

## Problem

Skills have no namespaces. An agent knows a skill by its frontmatter `name` (or its directory
name when `name` is missing), so two skills called `code-review` collide:

- inside one project: a project skill in `.skills/code-review` and `code-review` from
  `mattpocock/skills`, or two packages that both ship `code-review`;
- across levels: `~/.claude/skills/code-review` (personal) and the project's
  `.claude/skills/code-review`. Claude Code runs the personal one (enterprise > personal >
  project). Codex shows both (`$HOME/.agents/skills` is its USER scope, `.agents/skills` its REPO
  scope).

skillcask today manages only the project level and stops with an error on every collision inside
it. It cannot install personal skills at all.

## Goals

1. `skillcask --global` manages personal skills with the same manifest, lock and verification as
   a project.
2. A collision inside one level can be solved by installing the newcomer under another name, and
   skillcask offers that interactively.
3. A collision across levels is reported as a warning, since skillcask cannot decide which one the
   agent uses.

## Non-goals

- Automatic namespacing (`vendor-skill` for every skill). Every command and every skill's own
  documentation would stop matching.
- Rewriting references inside skill bodies (`/code-review`, "use the tdd skill") when a skill is
  renamed.
- Project skills (`[agents] local`) in the global scope.
- Enterprise / admin scopes (`/etc/codex/skills`, managed Claude settings).

## A. Global scope

`-g` / `--global` is a global flag for `init`, `add`, `remove`, `install`, `update`, `outdated`,
`status`, `doctor` and `search`. `publish` and plugin commands reject it; a plugin that wants
a global mode takes its own flag after the command name.

**Config directory**, first that is set: `$SKILLCASK_HOME`, `$XDG_CONFIG_HOME/skillcask`,
`~/.config/skillcask` (home from `HOME`, else `USERPROFILE`). It holds:

| File | |
|---|---|
| `skills.toml` | manifest, same format; created by the first `add -g` or by `init -g` |
| `skills.lock` | lock, same format |
| `auth.json` | read in place of the project's `./auth.json`; global Composer `auth.json` still applies |

The list of managed paths (the lines the project writes into its `.gitignore` block) is
`~/.agents/skills/.skillcask-installed`, not a file in the config directory: that directory is
meant to be synced through dotfiles, and a synced list would make `install -g` on another machine
replace a hand-written `~/.agents/skills/<name>` that the first machine had installed.

**Install root** is the home directory:

- store `~/.agents/skills` (Codex USER scope);
- targets from `[agents] targets`, relative to home, default `.claude/skills` and `.junie/skills`;
- `[agents] local` is an error in the global manifest.

**Differences from the project scope:**

| | project | global |
|---|---|---|
| managed list | `.gitignore` block | `~/.agents/skills/.skillcask-installed` |
| git index | managed paths untracked | not touched |
| link targets | relative (`../../.agents/skills/x`) | absolute (`/home/u/.agents/skills/x`) |
| link is OK when | its target equals the relative path | it resolves to the store directory (absolute or relative link, or a target directory that is itself a symlink to the store) |
| symlinked parents (`.claude -> dotfiles/claude`) | refused | allowed |
| hand-written skills in the store | linked into every target | left alone, not linked |

Reasons: home belongs to the user, so the symlink guard (against a repository that commits
`.agents/skills -> ~/.config`) does not apply, and dotfile managers commonly symlink `~/.claude`.
Relative links break under such parents, absolute ones do not. Hand-written skills are not linked
because the user may keep them in one agent's directory on purpose, and copies made by other
tools (`npx skills`) often already sit in `~/.claude/skills`.

A store directory in `~/.agents/skills` that skillcask does not manage and that a package wants
is a conflict (section B), as it is in a project.

`find_root` is not used with `--global`; running skillcask without `--global` under the home
directory never picks up the global manifest, because it is not named `~/skills.toml`. Run inside
the config directory itself, a project command stops with an error that points to `--global`.

## B. Install aliases

**Manifest.** A package entry takes `rename`, upstream skill name to install name:

```toml
"mattpocock/skills" = { github = true, version = "^1.3", rename = { code-review = "mattpocock-code-review" } }
"mattpocock/skills" = { github = true, skills = ["tdd", "code-review"], rename = { code-review = "mp-review" } }
```

- Works with and without `skills = [...]`; `skills` keeps upstream names.
- Values must be valid skill names and unique within the entry. A key that the resolved package
  does not provide is an error at resolve time (`no skill "x" in ... (it has: ...)`).
- `rename` on a string entry (`"a/b" = "^1.0"`) turns it into a table when skillcask writes it.

**Lock.** A renamed skill records its upstream name in `from`:

```toml
skills = [
  { name = "mattpocock-code-review", from = "code-review", path = "skills/code-review", tree-sha256 = "..." },
]
```

`name` is always the install name, so the store, links, gitignore block and status keep using
it. `tree-sha256` is the hash of the installed (renamed) tree. The rename is deterministic, so
`install` verifies the downloaded archive, applies the rename, and compares the hash as before.

**Rename.** In the installed copy, only the value of the frontmatter `name:` line of `SKILL.md`
changes. A `SKILL.md` without a `name:` line is left as it is; the directory name carries the new
name. Nothing else in the skill changes.

**Reconcile.** `install` re-resolves an entry when its `rename` differs from the lock (`rename
changed`). Selection comparison uses `from` when present.

**Conflicts** that offer an alias, with the package being added or resolved as the newcomer:

1. two packages provide the same install name;
2. a package skill has the name of a project skill in `[agents] local`;
3. the store or a target already holds a directory with that name that skillcask does not manage;
4. (`add` only) the new skill is shadowed by a personal skill (section C).

**Prompt.** In `add`, `update` and `install` without `--frozen`, when stdin and stderr are
terminals and `CI` is not set:

```
code-review (mattpocock/skills) conflicts with project skill .skills/code-review.
Install it as mattpocock-code-review? [Y/n/<other name>]
```

- The default name is `<vendor>-<skill>` (vendor: package name before `/`). If that name is taken
  too, the prompt asks for a name instead of offering a default.
- Yes or a name: skillcask writes `rename` into the manifest entry, resolves the package again and
  re-checks conflicts.
- No, or no terminal: the command fails as today, and the message names the fix:

  ```
  error: skill "code-review" is both a project skill in .skills and provided by mattpocock/skills
    to install it under another name, add to its entry in skills.toml:
    rename = { code-review = "mattpocock-code-review" }
  ```

For a shadow (case 4), "no" installs the skill unrenamed and prints the warning.

## C. Shadow warnings

Project scope only, and only when the project root is not the home directory. For every skill
name `n` the project installs (locked, project and hand-written) and every directory `d` among
the store and the targets: if `~/<d>/<n>` exists, warn.

```
warning: code-review: ~/.claude/skills/code-review shadows the project skill in Claude Code
warning: code-review: ~/.agents/skills/code-review also exists; the agent may show both
```

The Claude Code wording is used for `.claude/skills`, the generic one for every other directory.

- `install`, `add`, `update`: printed to stderr after installing; exit code unchanged.
- `doctor`: listed as `warning:` lines, not counted as problems; `--fix` does nothing for them.

## Testing

Integration tests in `tests/cli.rs` run with `HOME` and `SKILLCASK_HOME` pointed at temp dirs:

- `add -g`, `install -g --frozen`, `remove -g`: store, absolute links, `.skillcask-installed` file, no
  `.gitignore` written;
- `~/.claude` as a symlink to another directory: links work;
- a relative link from another tool pointing at the store counts as OK;
- a project skill shadowed by `~/.claude/skills/<n>`: warning in `install` and `doctor`, exit 0;
- `rename` in the manifest: installed under the new name, `SKILL.md` name rewritten, lock has
  `from`, `install --frozen` in a fresh clone verifies;
- a conflict without a terminal: error with the `rename = ...` hint.

Unit tests: frontmatter rename (with and without `name:`, with quoting), `rename` parsing and
validation, lock round trip with `from`. The interactive prompt is a thin function over a tested
decision (`conflict -> suggested name`); the terminal itself is not tested.

## Order

A (global), then C (shadow warnings, uses the home paths from A), then B (aliases and the prompt).
Small commits per task (see the plan), README updated with each part.
