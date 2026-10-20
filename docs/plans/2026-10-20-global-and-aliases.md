# Global scope, install aliases, shadow warnings: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** implement `docs/specs/2026-10-20-global-and-aliases.md`: `skillcask --global` for personal skills, `rename` aliases with a conflict prompt, and warnings when personal skills shadow project ones.

**Architecture:** a `Scope` value (install root, config dir, global flag) replaces the bare `root: &Path` in `Ctx` and `project.rs`; every global/project difference is a branch on `Scope::global` inside `project.rs`, so `materialize`, `preflight`, `status` and `doctor` stay shared. Aliases are a per-entry `rename` map in the manifest and a `from` field in the lock; the rename rewrites one frontmatter line before hashing, so lock verification is unchanged.

**Tech stack:** Rust 2024 edition, clap, toml_edit, ureq; tests via `cargo test` (unit tests in `src/*.rs`, integration tests in `tests/cli.rs` with the harness in `tests/common/mod.rs`).

**Conventions (read before any task):**
- Format with `cargo fmt` (max_width 140). CI runs `cargo fmt --check`, `cargo clippy --all-targets --locked -- -D warnings`, `cargo test --locked`. Every task ends with all three green.
- Comments: only for a non-obvious why. Match the surrounding terse style. No section-label comments.
- Error codes: `MANIFEST` (1) for user/config problems, `IO` (5). Use the `bail!` macro from `crate::bail`.
- Commits: `git commit` with Conventional Commits subject, body only when the why is not obvious, ending with the line
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Repo-local git email is already set; do not change git config.
- Tests run the real binary with `HOME`, `USERPROFILE`, `COMPOSER_HOME` pointed at a temp dir (`Project::run` in `tests/common/mod.rs`).

---

## File map

| File | Change |
|---|---|
| `src/scope.rs` (new) | `Scope { root, config, global }`, home and config dir resolution |
| `src/project.rs` | functions take `&Scope`; global branches: absolute links, no symlink guard, `installed` file instead of `.gitignore`, no git, no project/hand-written skills |
| `src/commands.rs` | `Ctx` holds a `Scope`; shadow warnings; conflict collection, hints, rename application, prompt |
| `src/main.rs` | `-g/--global`, scope construction, interactive detection |
| `src/manifest.rs` | `GLOBAL_TEMPLATE`, reject `local` in global, `rename` parse/write, `SkillReq` derives `Default` |
| `src/lock.rs` | `LockedSkill::from` |
| `src/skill.rs` | `rename_frontmatter` |
| `src/http.rs` | `Http::new` takes the config dir (for `auth.json`) |
| `tests/common/mod.rs` | `Project::home()`, `Project::global_run` helpers |
| `tests/cli.rs` | integration tests per part |
| `README.md` | docs per part |

---

# Part A: global scope

### Task 1: `Scope` and config dir resolution

**Files:**
- Create: `src/scope.rs`
- Modify: `src/main.rs:1-12` (add `mod scope;`)

- [ ] **Step 1: Write `src/scope.rs` with tests**

```rust
//! Where skillcask reads its manifest and writes skills: a project, or the user's home.

use std::path::{Path, PathBuf};

use crate::bail;
use crate::error::{MANIFEST, Result};

#[derive(Clone, Debug)]
pub struct Scope {
    /// Base of the store and the agent targets: the project root, or home.
    pub root: PathBuf,
    /// Holds skills.toml, skills.lock and auth.json: the project root, or the config dir.
    pub config: PathBuf,
    pub global: bool,
}

impl Scope {
    pub fn project(root: PathBuf) -> Scope {
        Scope { config: root.clone(), root, global: false }
    }

    pub fn global() -> Result<Scope> {
        let Some(home) = home() else { bail!(MANIFEST, "--global needs HOME (or USERPROFILE) to be set") };
        Ok(Scope { config: config_dir(&home, |k| std::env::var_os(k)), root: home, global: true })
    }

    /// `rel` (a path under `root`) as the user should read it in messages.
    pub fn show(&self, rel: &str) -> String {
        if self.global { format!("~/{rel}") } else { rel.to_string() }
    }
}

pub fn home() -> Option<PathBuf> {
    std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")).filter(|h| !h.is_empty()).map(PathBuf::from)
}

/// `$SKILLCASK_HOME`, else `$XDG_CONFIG_HOME/skillcask`, else `~/.config/skillcask`.
fn config_dir(home: &Path, var: impl Fn(&str) -> Option<std::ffi::OsString>) -> PathBuf {
    let set = |k: &str| var(k).filter(|v| !v.is_empty()).map(PathBuf::from);
    set("SKILLCASK_HOME")
        .or_else(|| set("XDG_CONFIG_HOME").map(|x| x.join("skillcask")))
        .unwrap_or_else(|| home.join(".config").join("skillcask"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_dir_precedence() {
        let home = Path::new("/h");
        let env = |pairs: &'static [(&'static str, &'static str)]| move |k: &str| pairs.iter().find(|(n, _)| *n == k).map(|(_, v)| v.into());
        assert_eq!(config_dir(home, env(&[])), Path::new("/h/.config/skillcask"));
        assert_eq!(config_dir(home, env(&[("XDG_CONFIG_HOME", "/x")])), Path::new("/x/skillcask"));
        assert_eq!(config_dir(home, env(&[("XDG_CONFIG_HOME", "/x"), ("SKILLCASK_HOME", "/s")])), Path::new("/s"));
        assert_eq!(config_dir(home, env(&[("SKILLCASK_HOME", "")])), Path::new("/h/.config/skillcask"));
    }
}
```

- [ ] **Step 2: Register the module** — add `mod scope;` to `src/main.rs` in alphabetical order (after `mod registry;`).

- [ ] **Step 3: Run** `cargo test scope` → `config_dir_precedence` passes. Clippy will report unused items until Task 2 uses them; do not add `#[allow]`, commit Tasks 1 and 2 together.

### Task 2: thread `Scope` through `project.rs`, `commands.rs`, `http.rs` (no behavior change)

Mechanical refactor. Project behavior must be byte-identical; the whole existing test suite is the check.

**Files:**
- Modify: `src/project.rs`, `src/commands.rs`, `src/http.rs:123`, `src/main.rs:123-127`

- [ ] **Step 1: `project.rs` signatures.** Every public function that takes `root: &Path` takes `s: &Scope` instead (`use crate::scope::Scope;`), and uses `s.root` where it used `root`: `store_dir`, `store_names`, `no_symlink`, `temp_dir`, `place`, `link_state`, `link`, `local_names`, `stale_local_links`, `unlink`, `read_modes`, `write_modes`, `read_block`, `block_managed`, `write_block`, `git_tracked`, `git_untrack`; private `read_gitignore` too. `link_target(at, source, name)` gains a first parameter, named `_s: &Scope` in this task (Task 3 renames it to `s` and adds the global branch). `rel(root, p)` and `find_root()` stay as they are.
  Update the unit tests at the bottom of `project.rs` to build `let s = Scope::project(dir.path().to_path_buf());` and pass `&s`.

- [ ] **Step 2: `http.rs`.** Rename the `Http::new(root: &Path, …)` parameter to `config: &Path` and `Auth::load(root)` to `Auth::load(config)`; it reads `config.join("auth.json")`. Same code, new name — the project passes its root, global (Task 4) passes the config dir.

- [ ] **Step 3: `commands.rs`.** `Ctx { pub s: Scope, … }` replaces `pub root: PathBuf`; `Ctx::new(s: Scope, verbose, limits)`. Replace:
  - manifest/lock paths (`Manifest::load`, `Lock::load`, `lock.save`, `manifest::write_skill`, `manifest::remove_skills`, `ctx.root.join(manifest::FILE)`, `init`'s path, `Http::new`) → `&self.s.config` / `&ctx.s.config`;
  - everything that touches the store, targets, gitignore, git (`project::*` calls, `tree_on_disk`, `installed_ok`, `hand_written`, `fetch`'s `temp_dir`) → `&self.s` / `&ctx.s`. Change helper signatures `tree_on_disk(s: &Scope, name)`, `installed_ok(s: &Scope, sk: &LockedSkill)`, `hand_written(s: &Scope, …)` accordingly.
  In `preflight`/`materialize`/`doctor`, the local `let root = &self.root;` becomes `let s = &self.s;`.

- [ ] **Step 4: `main.rs`.** `let ctx = Ctx::new(Scope::project(root), cli.verbose, limits);` with `use crate::scope::Scope;`.

- [ ] **Step 5: Verify.** `cargo fmt && cargo clippy --all-targets --locked -- -D warnings && cargo test --locked` → all tests that passed before still pass (24 unit + 22 integration, 1 ignored, plus `config_dir_precedence`).

- [ ] **Step 6: Commit** `refactor: pass a Scope instead of the project root` (includes `src/scope.rs`).

### Task 3: global behavior in `project.rs`

**Files:**
- Modify: `src/project.rs`

Each item below is a branch on `s.global`; the project branch keeps today's code.

- [ ] **Step 1: Write failing unit tests** (append to `mod tests` in `project.rs`):

```rust
    fn global_scope(home: &Path) -> Scope {
        Scope { root: home.to_path_buf(), config: home.join(".config/skillcask"), global: true }
    }

    #[cfg(unix)]
    #[test]
    fn global_links_are_absolute_and_survive_symlinked_parents() {
        let home = tempfile::tempdir().unwrap();
        let s = global_scope(home.path());
        std::fs::create_dir_all(store_dir(&s, "x")).unwrap();
        std::fs::write(store_dir(&s, "x").join(SKILL_MD), "s").unwrap();
        let dotfiles = tempfile::tempdir().unwrap();
        std::os::unix::fs::symlink(dotfiles.path(), home.path().join(".claude")).unwrap();
        no_symlink(&s, ".claude/skills").unwrap();
        assert!(!link(&s, ".claude/skills", STORE, "x").unwrap());
        assert_eq!(std::fs::read_link(home.path().join(".claude/skills/x")).unwrap(), home.path().join(".agents/skills/x"));
        assert_eq!(link_state(&s, ".claude/skills", STORE, "x"), LinkState::Ok);
        assert_eq!(std::fs::read_to_string(dotfiles.path().join("skills/x/SKILL.md")).unwrap(), "s");

        // A relative link made by another tool that reaches the same store dir is fine too.
        std::fs::create_dir_all(home.path().join(".junie/skills")).unwrap();
        std::os::unix::fs::symlink("../../.agents/skills/x", home.path().join(".junie/skills/x")).unwrap();
        assert_eq!(link_state(&s, ".junie/skills", STORE, "x"), LinkState::Ok);
    }

    #[test]
    fn global_block_lives_in_the_config_dir() {
        let home = tempfile::tempdir().unwrap();
        let s = global_scope(home.path());
        let managed: BTreeSet<String> = ["a".to_string()].into();
        assert!(write_block(&s, &block_lines(&managed, &[".claude/skills".into()], &BTreeSet::new())).unwrap());
        assert!(!home.path().join(".gitignore").exists());
        assert!(std::fs::read_to_string(home.path().join(".config/skillcask/installed")).unwrap().contains("/.agents/skills/a/"));
        assert_eq!(block_managed(&s).unwrap(), managed);
        assert!(git_tracked(&s, &["x".into()]).is_empty());
        std::fs::create_dir_all(home.path().join("p")).unwrap();
        std::fs::write(home.path().join("p/SKILL.md"), "").unwrap();
        assert!(local_names(&s, "").unwrap().is_empty(), "the global scope has no project skills");
    }
```

- [ ] **Step 2: Run** `cargo test --lib project` → the two new tests fail.

- [ ] **Step 3: Implement.**
  - `no_symlink(s, sub)`: `if s.global { return Ok(()); }` first line. Doc comment addition: home belongs to the user and dotfile managers symlink `~/.claude`.
  - `link_target(s, at, source, name)`: in global return `s.root` joined with every `/`-segment of `source`, then `name` (absolute; built per segment for Windows). Rename `_s` → `s`.
  - `link_state`: for a symlink in global, `Ok` when `std::fs::canonicalize(&path)` and `std::fs::canonicalize(s.root.join(source).join(name))` are both `Ok` and equal, and `path.join(SKILL_MD).is_file()`; else `Wrong`. Project branch unchanged.
  - New private `fn ignore_file(s: &Scope) -> PathBuf`: global → `s.config.join("installed")`, project → `s.root.join(".gitignore")`. `read_gitignore` and `write_block` use it; `write_block` calls `no_symlink(s, ".gitignore")` only in the project branch (it already returns early in global), and in global does `std::fs::create_dir_all(&s.config)?` before writing. Error texts that say `.gitignore` stay as they are (they only fire in the project).
  - `git_tracked`/`git_untrack`: `if s.global { return Vec::new() / Ok(()) }`.
  - `local_names`, `stale_local_links`: empty in global.
  - `store_names` unchanged (used by `hand_written`; Task 4 empties `hand_written` in global at the call site).

- [ ] **Step 4: Run** `cargo test --locked` → all pass.

- [ ] **Step 5: Commit** `feat: global scope layout in the store and link helpers`.

### Task 4: `--global` CLI, manifest, auth; integration tests

**Files:**
- Modify: `src/main.rs`, `src/manifest.rs`, `src/commands.rs`, `tests/common/mod.rs`, `tests/cli.rs`

- [ ] **Step 1: Test harness.** In `tests/common/mod.rs` add to `impl Project`:

```rust
    pub fn home(&self) -> &Path {
        self.home.path()
    }

    /// `skillcask --global <args>` with the config dir at `~/.config/skillcask` of the fake home.
    pub fn global(&self, args: &[&str], code: i32) -> String {
        let mut a = vec!["--global"];
        a.extend_from_slice(args);
        self.expect(&a, code)
    }

    pub fn global_manifest(&self, server: &Server, skills: &str) {
        let dir = self.home().join(".config/skillcask");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("skills.toml"),
            format!(
                "[repositories]\nfix = {{ type = \"composer\", url = \"{}\" }}\n\n[skills]\n{skills}\n[policy]\npackagist = false\n",
                server.url("/packages.json")
            ),
        )
        .unwrap();
    }
```

  `Project::run` also gets `.env_remove("SKILLCASK_HOME").env_remove("XDG_CONFIG_HOME")` so the developer's environment does not leak in.

- [ ] **Step 2: Write failing integration tests** in `tests/cli.rs`:

```rust
#[test]
fn global_add_install_remove() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let p = Project::new(&s);
    p.global_manifest(&s, "");
    let h = p.home().to_path_buf();
    std::fs::create_dir_all(h.join(".agents/skills/mine")).unwrap();
    std::fs::write(h.join(".agents/skills/mine/SKILL.md"), skill_md("mine")).unwrap();

    p.global(&["add", "acme/one"], 0);
    let cfg = h.join(".config/skillcask");
    assert!(std::fs::read_to_string(cfg.join("skills.toml")).unwrap().contains("\"acme/one\""));
    assert!(cfg.join("skills.lock").is_file());
    assert_eq!(std::fs::read_to_string(h.join(".agents/skills/one/SKILL.md")).unwrap(), skill_md("one"));
    if cfg!(unix) {
        assert_eq!(std::fs::read_link(h.join(".claude/skills/one")).unwrap(), h.join(".agents/skills/one"));
    }
    assert!(std::fs::read_to_string(cfg.join("installed")).unwrap().contains("/.claude/skills/one"));
    assert!(!h.join(".gitignore").exists() && !p.exists("skills.toml") && !p.exists(".agents"), "nothing written to the project or ~/.gitignore");
    assert!(!h.join(".claude/skills/mine").exists(), "hand-written personal skills are not linked");

    p.global(&["status"], 0);
    p.global(&["doctor"], 0);
    std::fs::remove_dir_all(h.join(".agents/skills/one")).unwrap();
    let mut ci = p;
    ci.env.push(("CI".into(), "true".into()));
    ci.global(&["install"], 0);
    assert!(h.join(".agents/skills/one/SKILL.md").is_file());

    ci.global(&["remove", "acme/one"], 0);
    assert!(!h.join(".agents/skills/one").exists() && !h.join(".claude/skills/one").exists());
    assert!(h.join(".agents/skills/mine/SKILL.md").is_file());
}

#[cfg(unix)]
#[test]
fn global_follows_symlinked_dotfiles() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let p = Project::new(&s);
    p.global_manifest(&s, "");
    let dotfiles = tempfile::tempdir().unwrap();
    std::os::unix::fs::symlink(dotfiles.path(), p.home().join(".claude")).unwrap();
    p.global(&["add", "acme/one"], 0);
    assert_eq!(std::fs::read_to_string(dotfiles.path().join("skills/one/SKILL.md")).unwrap(), skill_md("one"));
}

#[test]
fn global_flag_rules() {
    let s = Server::start();
    let p = Project::new(&s);
    p.global(&["init"], 0);
    let text = std::fs::read_to_string(p.home().join(".config/skillcask/skills.toml")).unwrap();
    assert!(!text.contains("local"), "{text}");
    p.global(&["init"], 1);
    std::fs::write(p.home().join(".config/skillcask/skills.toml"), "[agents]\nlocal = \".skills\"\n").unwrap();
    assert!(p.global(&["install"], 1).contains("agents.local"));
    assert!(p.global(&["publish", "--vendor", "v", "--base-url", "https://x", "--out", "o"], 1).contains("--global"));
    assert!(p.global(&["some-plugin"], 1).contains("--global"));
    let mut custom = p;
    let dir = tempfile::tempdir().unwrap();
    custom.env.push(("SKILLCASK_HOME".into(), dir.path().display().to_string()));
    custom.global(&["init"], 0);
    assert!(dir.path().join("skills.toml").is_file());
}
```

- [ ] **Step 3: Run** `cargo test --test cli global` → fail (unknown `--global`).

- [ ] **Step 4: Implement `main.rs`.**
  - `Cli` gets `/// Manage personal skills in ~/.agents/skills instead of the project's. #[arg(short, long, global = true)] global: bool,`.
  - In `run`: before the plugin branch, `if cli.global && matches!(cli.cmd, Cmd::External(_) | Cmd::Publish { .. }) { return Err(Error::new(MANIFEST, "--global does not apply to this command")); }`.
  - Scope: `let scope = if cli.global { Scope::global()? } else { Scope::project(match cli.cmd { Cmd::Init | Cmd::Publish { .. } => std::env::current_dir()?, _ => project::find_root()? }) };`.

- [ ] **Step 5: Implement `manifest.rs`.**
  - `pub const GLOBAL_TEMPLATE: &str` — `TEMPLATE` without the `local = ...` line, and the header line `# skillcask global manifest: personal skills in ~/.agents/skills. Lock: skills.lock.`
  - `pub fn template(global: bool) -> &'static str`.
  - `Manifest::load(dir: &Path, global: bool)`; `parse(text, global)`: in global, an explicit `[agents] local` is `bad("agents.local is not supported with --global; personal skills go straight into ~/.agents/skills")`. Leave `local` as `DEFAULT_LOCAL` (unused: `local_names` is empty in global). The `targets.contains(&local)` check runs only in the project. Update all `parse(` callers (tests use `false`) and the `edit` helper (`parse(&doc.to_string(), false)` is fine: global manifests never contain `local`, and `edit` only validates).
  - `"skills.toml not found; run `skillcask init`"`: in global say `run `skillcask init --global``.

- [ ] **Step 6: Implement `commands.rs`.**
  - `manifest_or_default` and `finish_add` use `manifest::template(self.s.global)`; `init` and `finish_add` call `std::fs::create_dir_all(&ctx.s.config)?` before writing.
  - All `Manifest::load(x)` → `Manifest::load(x, ctx.s.global)`.
  - `hand_written`: return an empty set when `s.global` (spec: personal hand-written skills are left alone).
  - In messages that name store/target paths (`preflight`: `"{STORE}/{n} exists…"`, `"{t}/{n} exists…"`; `doctor`: `"{at}/{n}: link …"`, `"{STORE}/{n}: not installed…"`), wrap the path in `s.show(...)` so global errors read `~/.claude/skills/x`. Project output must stay identical (existing tests assert `.claude/skills/mine exists`).

- [ ] **Step 7: Run** `cargo fmt && cargo clippy --all-targets --locked -- -D warnings && cargo test --locked` → all pass.

- [ ] **Step 8: README.** Add a `### Personal skills (--global)` section after the `skills.toml` section:

```markdown
### Personal skills (`--global`)

`skillcask --global` (`-g`) manages skills for your user instead of a project, with the same
manifest, lock and verification:

```sh
skillcask -g add github:mattpocock/skills/grill-me
skillcask -g install --frozen    # e.g. from a dotfiles repository
```

- `skills.toml`, `skills.lock` and an optional `auth.json` live in `~/.config/skillcask`
  (`$XDG_CONFIG_HOME/skillcask`; `SKILLCASK_HOME` overrides both). Keep them in your dotfiles.
- Skills go to `~/.agents/skills` (read by Codex), with links in `~/.claude/skills` and
  `~/.junie/skills` (`[agents] targets`, relative to home). Links are absolute, so a symlinked
  `~/.claude` works. `[agents] local` does not apply.
- Personal skills you wrote by hand stay where they are and are not linked anywhere.
- The list of managed paths is `~/.config/skillcask/installed`; nothing touches git.
```

  Add `-g, --global` to the commands table intro line: "Every command except `publish` takes `--global`."

- [ ] **Step 9: Commit** `feat: --global manages personal skills in ~/.agents/skills`.

---

# Part C: shadow warnings

### Task 5: warn when personal skills shadow project skills

**Files:**
- Modify: `src/commands.rs`, `tests/cli.rs`, `README.md`

- [ ] **Step 1: Write the failing integration test:**

```rust
#[test]
fn personal_skills_shadowing_project_ones_are_warned_about() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    p.write(".skills/mine/SKILL.md", &skill_md("mine"));
    for d in [".claude/skills/one", ".agents/skills/mine"] {
        std::fs::create_dir_all(p.home().join(d)).unwrap();
        std::fs::write(p.home().join(d).join("SKILL.md"), "personal").unwrap();
    }
    let out = p.ok(&["install"]);
    assert!(out.contains("warning: one: ~/.claude/skills/one shadows the project skill in Claude Code"), "{out}");
    assert!(out.contains("warning: mine: ~/.agents/skills/mine also exists; the agent may show both"), "{out}");
    let out = p.ok(&["doctor"]);
    assert!(out.contains("warning: one:") && out.contains("no problems found"), "{out}");
    assert!(!p.global(&["init"], 0).contains("warning"));
}
```

- [ ] **Step 2: Run** `cargo test --test cli shadow` → fail.

- [ ] **Step 3: Implement** in `commands.rs`:

```rust
/// Personal skills with the same name as project ones. Claude Code runs the personal one;
/// Codex lists both. Empty for the global scope.
fn shadows<'a>(s: &Scope, m: &Manifest, names: impl IntoIterator<Item = &'a String>) -> Vec<String> {
    let Some(home) = crate::scope::home().filter(|h| !s.global && std::fs::canonicalize(h).ok() != std::fs::canonicalize(&s.root).ok())
    else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for n in names {
        for d in std::iter::once(STORE).chain(m.targets.iter().map(String::as_str)) {
            if home.join(d).join(n).symlink_metadata().is_ok() {
                out.push(if d == ".claude/skills" {
                    format!("{n}: ~/{d}/{n} shadows the project skill in Claude Code")
                } else {
                    format!("{n}: ~/{d}/{n} also exists; the agent may show both")
                });
            }
        }
    }
    out
}
```

  - End of `materialize` (before `Ok(())`): `for w in shadows(s, m, locked.keys().chain(&hand).chain(&locals)) { eprintln!("warning: {w}"); }`.
  - `doctor`: after the checks, `for w in shadows(...same names...) { println!("warning: {w}"); }` — not added to `open`.

- [ ] **Step 4: Run** full check (fmt, clippy, test) → pass.

- [ ] **Step 5: README** — in the paragraph about project skills, add: "When a skill with the same name exists in your home (`~/.claude/skills`, `~/.agents/skills`, …), `install` and `doctor` print a warning: Claude Code runs the personal one, Codex lists both."

- [ ] **Step 6: Commit** `feat: warn when personal skills shadow project skills`.

---

# Part B: install aliases

### Task 6: `skill::rename_frontmatter`

**Files:**
- Modify: `src/skill.rs`

- [ ] **Step 1: Failing unit test** in `skill.rs` tests:

```rust
    #[test]
    fn renames_frontmatter_name_only() {
        let t = "---\nname: code-review\ndescription: name: x\n---\n# name: code-review\n";
        assert_eq!(rename_frontmatter(t, "mp-review"), "---\nname: mp-review\ndescription: name: x\n---\n# name: code-review\n");
        assert_eq!(rename_frontmatter("---\r\nname: \"a\"\r\n---\r\n", "b"), "---\r\nname: b\r\n---\r\n");
        assert_eq!(rename_frontmatter("\u{feff}---\nname: a\n---\n", "b"), "\u{feff}---\nname: b\n---\n");
        let no_name = "---\ndescription: d\n---\nname: a\n";
        assert_eq!(rename_frontmatter(no_name, "b"), no_name);
        assert_eq!(rename_frontmatter("# no frontmatter", "b"), "# no frontmatter");
        assert_eq!(frontmatter(&rename_frontmatter(t, "mp-review"))["name"], "mp-review");
    }
```

- [ ] **Step 2: Run** `cargo test --lib renames_frontmatter` → fails to compile (no function).

- [ ] **Step 3: Implement:**

```rust
/// Sets the frontmatter `name:` value, keeping every other byte. No frontmatter or no `name:`
/// line: unchanged, since the directory name then names the skill.
pub fn rename_frontmatter(text: &str, to: &str) -> String {
    let body = text.strip_prefix('\u{feff}').unwrap_or(text);
    let bom = &text[..text.len() - body.len()];
    let mut lines = body.split_inclusive('\n');
    if lines.next().map(str::trim_end) != Some("---") {
        return text.to_string();
    }
    let mut at = body.find('\n').map_or(body.len(), |i| i + 1);
    for line in lines {
        let content = line.trim_end_matches(['\n', '\r']);
        if content.trim_end() == "---" {
            break;
        }
        if content.starts_with("name:") {
            let eol = &line[content.len()..];
            return format!("{bom}{}name: {to}{eol}{}", &body[..at], &body[at + line.len()..]);
        }
        at += line.len();
    }
    text.to_string()
}
```

- [ ] **Step 4: Run** test → pass; clippy clean.

- [ ] **Step 5: Commit** together with Task 7.

### Task 7: `rename` in the manifest, `from` in the lock

**Files:**
- Modify: `src/manifest.rs`, `src/lock.rs`, `src/commands.rs` (construction sites only)

- [ ] **Step 1: Failing unit tests.**
  In `manifest.rs` `defaults_and_rejections` add:

```rust
        let r = |entry: &str| parse(&format!("[skills]\n\"a/b\" = {entry}"), false);
        let ok = r(r#"{ version = "^1.0", rename = { code-review = "mp-review" } }"#).unwrap();
        assert_eq!(ok.skills[0].rename, BTreeMap::from([("code-review".to_string(), "mp-review".to_string())]));
        assert!(r(r#"{ version = "^1.0", rename = { a = "Bad Name" } }"#).is_err());
        assert!(r(r#"{ version = "^1.0", rename = { a = "x", b = "x" } }"#).is_err());
        assert!(r(r#"{ version = "^1.0", rename = ["x"] }"#).is_err());
        assert!(r(r#"{ version = "^1.0", rename = { a = "a" } }"#).unwrap().skills[0].rename.is_empty(), "identity renames are dropped");
```

  In `edits_keep_comments` add a round trip:

```rust
        let renamed = SkillReq { rename: BTreeMap::from([("x".into(), "y".into())]), ..req.clone() };
        write_skill(dir.path(), &renamed).unwrap();
        let text = std::fs::read_to_string(dir.path().join(FILE)).unwrap();
        assert!(text.contains(r#"rename = { x = "y" }"#), "{text}");
        assert_eq!(parse(&text, false).unwrap().skills, [renamed]);
```

  In `lock.rs` `round_trip_is_byte_stable`, give the second skill `from: Some("orig".into())` and the first `from: None`; assert `text.contains("{ name = \"two\", from = \"orig\", path")`; add `assert!(parse(&text.replace("from = \"orig\"", "from = \"../x\"")).is_err());`.

- [ ] **Step 2: Run** `cargo test --lib` → compile errors (no field).

- [ ] **Step 3: Implement.**
  - `SkillReq` derives `Default` (`GitHub` needs nothing: it is inside `Option`) and gets `pub rename: BTreeMap<String, String>` (upstream → install name; `use std::collections::BTreeMap;`). Replace struct literals in `manifest.rs` and `commands.rs` (`add`, `add_github`) with `..Default::default()` where fields are left empty.
  - Parse (`manifest.rs` table branch): `rename` must be an inline table or table of strings: `bad(format!("{name}: rename must be a table of skill = \"new-name\""))`. Each value: `skill::valid_name` else `bad(format!("{name}: rename: {v:?} is not a valid skill name ([a-z0-9][a-z0-9-]*)"))`. Duplicate values: `bad(format!("{name}: rename: two skills renamed to {v:?}"))`. Drop entries where key == value.
  - `write_skill`: the string shorthand applies only when `req.rename.is_empty()` too; otherwise insert `rename` as an `InlineTable` of string values after `skills`.
  - `LockedSkill` gets `pub from: Option<String>` ("upstream name when installed under another one"). `render`: `{ name = …, from = … , path = …, tree-sha256 = … }` with `from` only when `Some`. `parse`: optional `from`, validated with `skill::valid_name` in the same check as `name`.
  - `commands.rs` `LockedSkill { … }` literal in `lock_candidate` gets `from: None` (Task 8 fills it).

- [ ] **Step 4: Run** full check → pass.

- [ ] **Step 5: Commit** `feat: rename field in skills.toml and from in skills.lock` (with Task 6).

### Task 8: apply renames on resolve and install

**Files:**
- Modify: `src/commands.rs`, `tests/cli.rs`

- [ ] **Step 1: Failing integration test:**

```rust
#[test]
fn renamed_skill_installs_under_its_new_name() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = { version = \"^1.0\", rename = { one = \"acme-one\" } }\n");
    p.ok(&["install"]);
    assert_eq!(p.read(".agents/skills/acme-one/SKILL.md"), skill_md("one").replacen("name: one", "name: acme-one", 1));
    assert!(p.exists(".claude/skills/acme-one/SKILL.md") && !p.exists(".agents/skills/one"));
    assert!(p.read("skills.lock").contains("{ name = \"acme-one\", from = \"one\", path = \"\""), "{}", p.read("skills.lock"));
    p.ok(&["status"]);
    p.ok(&["doctor"]);

    let mut ci = clone_of(&p, &s);
    ci.env.push(("CI".into(), "true".into()));
    ci.ok(&["install"]);
    assert_eq!(ci.read(".agents/skills/acme-one/SKILL.md"), p.read(".agents/skills/acme-one/SKILL.md"));

    p.manifest(&s, "\"acme/one\" = { version = \"^1.0\", rename = { one = \"other\" } }\n");
    assert!(p.expect(&["install", "--frozen"], 1).contains("rename changed"));
    p.ok(&["install"]);
    assert!(p.exists(".agents/skills/other") && !p.exists(".agents/skills/acme-one"));

    p.manifest(&s, "\"acme/one\" = { version = \"^1.0\", rename = { nope = \"x\" } }\n");
    assert!(p.expect(&["install"], 1).contains("rename: no skill \"nope\""));
}
```

- [ ] **Step 2: Run** `cargo test --test cli renamed` → fail.

- [ ] **Step 3: Implement.**
  - New method on `Fetched`:

```rust
    /// The skill's files as installed under `to`: SKILL.md gets the new frontmatter name, on disk
    /// too, so `place` copies the renamed file. Idempotent; `add` and `install` both call it.
    fn renamed_files(&self, mut files: Vec<FileEntry>, dir: &str, to: &str) -> Result<Vec<FileEntry>> {
        let path = self.dir.path().join(dir).join(skill::SKILL_MD);
        let text = std::fs::read_to_string(&path)?;
        let new = skill::rename_frontmatter(&text, to);
        std::fs::write(&path, &new)?;
        if let Some(e) = files.iter_mut().find(|e| e.path == skill::SKILL_MD) {
            *e = FileEntry::new(e.path.clone(), e.exec, new.as_bytes());
        }
        Ok(files)
    }
```

  - `lock_candidate`: after `found.retain(...)`/selection, check every `req.rename` key is in `found` (same error style as selection: `"{}: rename: no skill {k:?} in {} (it has: {})"`). In the loop building `skills`: `let to = req.rename.get(&name).cloned();`, `let mut files = f.skill_files(...)?; if let Some(t) = &to { files = f.renamed_files(files, &dir, t)?; }`, push `LockedSkill { name: to.clone().unwrap_or(name.clone()), from: to.map(|_| name), path: dir, tree_sha256 }`. The duplicate check (`appears twice in the package`) compares install names.
  - `materialize`: for each `s` needing install, `let mut files = f.skill_files(&p.name, &s.name, &s.path)?; if s.from.is_some() { files = f.renamed_files(files, &s.path, &s.name)?; }` before hashing.
  - `reconcile`: the selection comparison uses `s.from.as_ref().unwrap_or(&s.name)`; add a branch after it:

```rust
            Some(p) if {
                let locked: BTreeMap<&String, &String> = p.skills.iter().filter_map(|s| s.from.as_ref().map(|f| (f, &s.name))).collect();
                locked != req.rename.iter().collect()
            } => Some("rename changed".to_string()),
```

- [ ] **Step 4: Run** full check → pass.

- [ ] **Step 5: README** — in `skills.toml` example add a line
  `"mattpocock/skills" = { github = true, skills = ["tdd", "code-review"], rename = { code-review = "mp-code-review" } }` and a short `### Name conflicts` section:

```markdown
### Name conflicts

Skills have no namespaces: an agent knows a skill by its name. Two skills with the same name in
one project are an error. Install one of them under another name with `rename`:

```toml
"mattpocock/skills" = { github = true, rename = { code-review = "mp-code-review" } }
```

skillcask then installs `.agents/skills/mp-code-review` and changes the `name:` line in its
`SKILL.md`; the lock records the original name and the hash of the renamed copy. Nothing else in
the skill changes, so text that mentions the old name (`/code-review`) stays as it is.
`add`, `install` and `update` offer the rename when they hit a conflict in a terminal.
```

- [ ] **Step 6: Commit** `feat: install a skill under another name with rename`.

### Task 9: collect conflicts, hint the fix

Turns the bail-on-first conflict checks into a list, so Task 10 can act on them, and adds the `rename = …` hint to every error.

**Files:**
- Modify: `src/commands.rs`, `tests/cli.rs`

- [ ] **Step 1: Failing test** — extend `collisions_are_errors` (keep its existing asserts):

```rust
    // after the first `install` that fails with both package names:
    assert!(out.contains("rename = { same = \"other-same\" }"), "{out}");
```

  and in `project_skills_in_dot_skills_are_linked_and_committable`, change the last line to:

```rust
    let out = p.expect(&["install"], 1);
    assert!(out.contains("both a project skill") && out.contains("rename = { one = \"acme-one\" }"), "{out}");
```

- [ ] **Step 2: Run** → fail.

- [ ] **Step 3: Implement.**

```rust
/// A skill that cannot be installed under its name.
struct Conflict {
    package: String,
    /// Name inside the package (`from`, else the install name): the key for `rename`.
    upstream: String,
    msg: String,
}

/// `<vendor>-<skill>`, unless taken or not a valid name.
fn suggest(package: &str, upstream: &str, taken: &BTreeSet<String>) -> Option<String> {
    let vendor: String = package.split('/').next().unwrap_or("").chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect();
    let name = format!("{vendor}-{upstream}");
    (skill::valid_name(&name) && !taken.contains(&name)).then_some(name)
}

fn hint(c: &Conflict, taken: &BTreeSet<String>) -> String {
    let to = suggest(&c.package, &c.upstream, taken).unwrap_or_else(|| "<new-name>".into());
    format!(
        "{}\n  to install it under another name, add to its entry in {}:\n  rename = {{ {} = \"{to}\" }}",
        c.msg,
        manifest::FILE,
        c.upstream
    )
}
```

  - `fn taken_names(&self, m, lock) -> Result<BTreeSet<String>>`: lock install names ∪ `local_names` ∪ `store_names` ∪ entry names of every target dir that exist (read_dir, ignore errors).
  - `fn conflicts(&self, m: &Manifest, lock: &Lock, newcomers: &BTreeSet<String>) -> Result<Vec<Conflict>>` — the four checks of today's `locked_names` + `preflight`, in this order, pushing instead of bailing, same message texts:
    1. pkg vs pkg: iterate `lock.skills()` with packages in `newcomers` last, keep the first owner per install name; a second owner yields `Conflict { package: second, msg: "skill {n:?} is provided by both {first} and {second}" }`.
    2. project skill: `"skill {n:?} is both a project skill in {} and provided by {}"`.
    3. foreign store dir (`s.show(...)` path), 4. foreign target dir — as in today's `preflight`.
    Checks 2–4 iterate the de-duplicated `BTreeMap` from step 1.
  - `preflight(m, lock)` keeps the `no_symlink` loop, then `if let Some(c) = self.conflicts(m, lock, &BTreeSet::new())?.first() { bail!(MANIFEST, "{}", hint(c, &self.taken_names(m, lock)?)); }`.
  - `install`/`update` currently call `locked_names(&lock)?` before `lock.save`; replace with `ctx.preflight(&m, &lock)?` so the hint shows and nothing is saved on conflict. `locked_names` stays for `materialize`/`doctor` (it can no longer fail after preflight, keep its error anyway).

- [ ] **Step 4: Run** full check → pass (existing messages unchanged, hints appended).

- [ ] **Step 5: Commit** `feat: name the rename fix in conflict errors`.

### Task 10: interactive rename prompt

**Files:**
- Modify: `src/commands.rs`, `src/main.rs`

- [ ] **Step 1: Failing unit tests** in a new `#[cfg(test)] mod tests` at the bottom of `commands.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn suggestion_and_answers() {
        let taken: BTreeSet<String> = ["code-review".into(), "mattpocock-taken".into()].into();
        assert_eq!(suggest("mattpocock/skills", "code-review", &taken).as_deref(), Some("mattpocock-code-review"));
        assert_eq!(suggest("my_org.x/skills", "a", &taken).as_deref(), Some("my-org-x-a"));
        assert_eq!(suggest("mattpocock/skills", "taken", &taken), None);
        let s = Some("mp-x");
        assert_eq!(answer("", s, &taken), Answer::Use("mp-x".into()));
        assert_eq!(answer("Y", s, &taken), Answer::Use("mp-x".into()));
        assert_eq!(answer("n", s, &taken), Answer::Decline);
        assert_eq!(answer("mine", s, &taken), Answer::Use("mine".into()));
        assert!(matches!(answer("", None, &taken), Answer::Retry(_)));
        assert!(matches!(answer("Bad Name", s, &taken), Answer::Retry(_)));
        assert!(matches!(answer("code-review", s, &taken), Answer::Retry(_)));
    }
}
```

- [ ] **Step 2: Run** → compile error.

- [ ] **Step 3: Implement the decision and prompt.**

```rust
#[derive(Debug, PartialEq)]
enum Answer {
    Use(String),
    Decline,
    Retry(String),
}

fn answer(input: &str, suggestion: Option<&str>, taken: &BTreeSet<String>) -> Answer {
    match input.trim() {
        "" | "y" | "Y" | "yes" => match suggestion {
            Some(s) => Answer::Use(s.into()),
            None => Answer::Retry("type a name".into()),
        },
        "n" | "N" | "no" => Answer::Decline,
        n if !skill::valid_name(n) => Answer::Retry(format!("{n:?} is not a valid skill name ([a-z0-9][a-z0-9-]*)")),
        n if taken.contains(n) => Answer::Retry(format!("{n:?} is taken too")),
        n => Answer::Use(n.into()),
    }
}

/// Asks on stderr/stdin for an install name; None when declined or stdin is closed.
fn ask(question: &str, suggestion: Option<&str>, taken: &BTreeSet<String>) -> Result<Option<String>> {
    loop {
        match suggestion {
            Some(s) => eprint!("{question}\nInstall it as {s}? [Y/n/<other name>] "),
            None => eprint!("{question}\nInstall it under which name? (empty line: no) "),
        }
        let mut line = String::new();
        if std::io::stdin().read_line(&mut line)? == 0 {
            return Ok(None);
        }
        if suggestion.is_none() && line.trim().is_empty() {
            return Ok(None);
        }
        match answer(&line, suggestion, taken) {
            Answer::Use(n) => return Ok(Some(n)),
            Answer::Decline => return Ok(None),
            Answer::Retry(why) => eprintln!("{why}"),
        }
    }
}
```

- [ ] **Step 4: Interactivity flag.** `Ctx` gets `pub interactive: bool`; `Ctx::new(s, verbose, limits, interactive)`. In `main.rs`: `use std::io::IsTerminal;` and `let interactive = !ci() && std::io::stdin().is_terminal() && std::io::stderr().is_terminal();`. `install` passes `frozen || ci()` already; prompts never run when frozen because frozen bails before resolving.

- [ ] **Step 5: Rename application.** Methods on `Ctx`:

```rust
    /// Installs `upstream` of `pkg` as `to`: rewrites its lock entry from the prepared download.
    fn rename_locked(&self, lock: &mut Lock, prepared: &HashMap<String, Fetched>, pkg: &str, upstream: &str, to: &str) -> Result<()> {
        let f = prepared.get(pkg).expect("newcomers are prepared");
        let p = lock.packages.iter_mut().find(|p| p.name == pkg).expect("conflicts name locked packages");
        let s = p.skills.iter_mut().find(|s| s.from.as_deref().unwrap_or(&s.name) == upstream).expect("conflicts name locked skills");
        let files = f.renamed_files(f.skill_files(pkg, upstream, &s.path)?, &s.path, to)?;
        s.tree_sha256 = skill::tree_hash(&files);
        s.from = Some(upstream.to_string());
        s.name = to.to_string();
        p.skills.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(())
    }

    /// Offers a rename for each conflict of a newly resolved package; returns the manifest entries
    /// that changed. Without a terminal, does nothing: `preflight` then fails with the hint.
    fn settle_conflicts(
        &self,
        m: &Manifest,
        lock: &mut Lock,
        prepared: &HashMap<String, Fetched>,
        newcomers: &BTreeSet<String>,
        shadows_too: bool,
    ) -> Result<Vec<SkillReq>> {
        let mut changed: BTreeMap<String, SkillReq> = BTreeMap::new();
        if !self.interactive {
            return Ok(Vec::new());
        }
        loop {
            let taken = self.taken_names(m, lock)?;
            let Some(c) = self.conflicts(m, lock, newcomers)?.into_iter().find(|c| newcomers.contains(&c.package)) else { break };
            let Some(to) = ask(&format!("{} ({})", c.msg, c.package), suggest(&c.package, &c.upstream, &taken).as_deref(), &taken)? else {
                break;
            };
            self.rename_locked(lock, prepared, &c.package, &c.upstream, &to)?;
            let req = changed.entry(c.package.clone()).or_insert_with(|| m.skill(&c.package).cloned().expect("newcomers are in the manifest"));
            req.rename.insert(c.upstream.clone(), to);
        }
        if shadows_too {
            // add only: the new skill would be hidden by a personal one in Claude Code.
            for (p, s) in lock.skills().filter(|(p, _)| newcomers.contains(&p.name)).map(|(p, s)| (p.name.clone(), s.clone())).collect::<Vec<_>>() {
                let Some(w) = shadows(&self.s, m, [&s.name]).into_iter().next() else { continue };
                let taken = self.taken_names(m, lock)?;
                let upstream = s.from.clone().unwrap_or(s.name.clone());
                if let Some(to) = ask(&format!("{w} ({p})"), suggest(&p, &upstream, &taken).as_deref(), &taken)? {
                    self.rename_locked(lock, prepared, &p, &upstream, &to)?;
                    let req = changed.entry(p.clone()).or_insert_with(|| m.skill(&p).cloned().expect("newcomers are in the manifest"));
                    req.rename.insert(upstream, to);
                }
            }
        }
        Ok(changed.into_values().collect())
    }
```

  `add`'s manifest is not written yet when conflicts are checked, so `m.skill(pkg)` is `None` there. Handle it by passing `add`'s in-memory `req` into the manifest view: in `finish_add`, build `let mut view = m.clone(); view.skills.retain(|r| r.name != req.name); view.skills.push(req.clone());` and call `settle_conflicts(&view, …)`; take the returned entry for `req.name` (if any) as the `req` to write.

- [ ] **Step 6: Wire it in.**
  - `finish_add`: after `lock.upsert(pkg)`: `let newcomers = BTreeSet::from([req.name.clone()]); let changed = ctx.settle_conflicts(&view, &mut lock, &prepared, &newcomers, true)?; let req = changed.into_iter().find(|r| r.name == req.name).unwrap_or_else(|| req.clone());` then `ctx.preflight(&view, &lock)?` and write `req` (not the original) with `manifest::write_skill`.
  - `install` (non-frozen branch, after resolving `needs`): `let newcomers = needs.iter().map(|r| r.name.clone()).collect(); for r in ctx.settle_conflicts(&m, &mut lock, &prepared, &newcomers, false)? { manifest::write_skill(&ctx.s.config, &r)?; }` then `ctx.preflight(&m, &lock)?; lock.save(...)`. Reload the manifest (`let m = Manifest::load(...)?`) after writing so `materialize` and the next `reconcile` see the rename.
  - `update`: same as install, with `newcomers` = the names resolved in the loop.
  - Lock entries renamed by `rename_locked` keep the package `constraint`, so the next `reconcile` sees `rename` matching and does not re-resolve.

- [ ] **Step 7: Run** full check → pass. Then a manual check in a real terminal (the only way to exercise `ask`):

```sh
cargo build && d=$(mktemp -d) && cd "$d" && mkdir -p .skills/grill-me && printf -- '---\nname: grill-me\ndescription: x\n---\n' > .skills/grill-me/SKILL.md \
  && /Volumes/projects/data/www/skilldeck/target/debug/skillcask add github:mattpocock/skills/grill-me
```

  Expected: the prompt `skill "grill-me" is both a project skill … Install it as mattpocock-grill-me? [Y/n/<other name>]`; Enter installs `.agents/skills/mattpocock-grill-me` and `skills.toml` has `rename = { grill-me = "mattpocock-grill-me" }`. Report the transcript (needs network; skip and say so if offline).

- [ ] **Step 8: Commit** `feat: offer a rename when a skill name conflicts`.

### Task 11: docs and spec status

- [ ] Update the v1 spec (`docs/specs/2026-10-19-skillcask-v1.md`; `docs/spec.md` if the move has not landed) Non-goals/decisions only if they contradict the new features (check for "project only" wording; add a decision row `D12 | --global manages ~/.agents/skills with its own manifest in ~/.config/skillcask | …` following the table style).
- [ ] Set `Status: implemented.` in `docs/specs/2026-10-20-global-and-aliases.md`.
- [ ] Full check; commit `docs: global scope and rename in the spec`.
