# self-update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `skillcask self-update [--dry-run]` reruns the release's shell installer for an installer-script install on Unix and names the update command for every other install (D52, `docs/specs/2026-10-30-self-update.md`).

**Architecture:** `self_check.rs` exposes the latest-version fetch and the SemVer comparison it already has. A new `self_update.rs` holds a pure `detect(exe, cargo_home, receipt_dir) -> Method`, the per-method command, and the Unix installer run (download to an unnamed temp file, `exec sh -s`). `main.rs` wires the subcommand like `self-check`.

**Tech Stack:** Rust, clap derive, `serde_json`, `tempfile`, the crate's `Http::anonymous`; tests through `tests/common` (local HTTPS `Server`, `Project`).

---

### Task 1: share the latest-version fetch

**Files:**
- Modify: `src/self_check.rs`

- [ ] **Step 1:** Move the URL check and fetch out of `run` into `pub fn https_url(var, default) -> Result<String>` and `pub fn latest_release(verbose) -> Result<Option<String>>`; add `pub fn is_newer(latest) -> bool`; make `RUNNING` `pub`. `run` calls them; behavior and messages stay the same.

```rust
pub const RUNNING: &str = env!("CARGO_PKG_VERSION");
pub const RELEASES: &str = "https://github.com/puniserv/skillcask/releases";

pub fn https_url(var: &str, default: &str) -> Result<String> {
    let url = std::env::var(var).ok().filter(|u| !u.is_empty()).unwrap_or_else(|| default.into());
    if url::Url::parse(&url).map_or(true, |u| u.scheme() != "https") {
        let shown = crate::http::shown_url(&url);
        return Err(Error::new(NETWORK, format!("refusing non-HTTPS URL {shown}")).hint(format!("{var} must be an https:// URL")));
    }
    Ok(url)
}

pub fn latest_release(verbose: bool) -> Result<Option<String>> {
    let url = https_url("SKILLCASK_SELF_CHECK_URL", URL)?;
    let shown = crate::http::shown_url(&url);
    let hint = format!("check the connection; releases are listed at {RELEASES}");
    let body = crate::http::Http::anonymous(verbose)?
        .get(&url, LIMIT)
        .map_err(|e| Error { code: NETWORK, hint: Some(hint.clone()), ..e })?
        .ok_or_else(|| Error::new(NETWORK, format!("{shown}: not found")).hint(hint))?;
    let latest = latest(&body);
    if latest.is_none() {
        ui::warn(format!("{shown}: no version \"X.Y.Z\" skillcask can read"));
    }
    Ok(latest)
}

pub fn is_newer(latest: &str) -> bool {
    semver_cmp(latest, RUNNING) == Ordering::Greater
}
```

- [ ] **Step 2:** `cargo test --locked --test self_check` and `cargo test --locked self_check` — all pass unchanged.

### Task 2: detect the install method

**Files:**
- Create: `src/self_update.rs` (detection + unit tests)

- [ ] **Step 1: failing unit tests** in `src/self_update.rs` `mod tests`, on a temp dir:
  - `/opt/homebrew/Cellar/skillcask/0.10.1/bin/skillcask` → `Homebrew`
  - `/Applications/Skillcask.app/Contents/Helpers/skillcask` → `App`
  - `.../lib/node_modules/skillcask/node_modules/.bin_skillcask` → `Npm`
  - exe in `<cargo>/bin`, `.crates2.json` listing `skillcask 0.10.1 (registry+…)` and a receipt → `Cargo` (crates2 wins)
  - same exe, receipt `{"install_layout":"cargo-home","install_prefix":"<cargo>"}`, no crates2 → `Installer(<cargo>)`
  - receipt with `flat` layout, or a prefix whose `bin` is not the exe's dir, or `.crates2.json` of another `CARGO_HOME` → `Unknown`
- [ ] **Step 2:** `cargo test --locked self_update` — fails (no `detect`).
- [ ] **Step 3:** implement `enum Method { App, Homebrew, Npm, Cargo, Installer(PathBuf), Unknown }` and `detect`: path markers on the `/`-normalised string, then `.crates2.json` `installs` keys starting with `skillcask ` with the exe in `<cargo_home>/bin`, then the receipt; directories compared after `canonicalize`.
- [ ] **Step 4:** tests pass.

### Task 3: the command

**Files:**
- Modify: `src/self_update.rs`, `src/main.rs`

- [ ] **Step 1:** `pub fn run(verbose, dry_run)`: unknown latest → exit 1 with the releases page; not newer → `skillcask X is the latest`, exit 0; `Installer(prefix)` on Unix → `installer()`; any other method → `Error::new(MANIFEST, "skillcask X -> Y: installed with <method>; update it there").hint(<command>)`.
- [ ] **Step 2:** `installer()` (Unix): `https_url("SKILLCASK_SELF_UPDATE_URL", <tag url>)`; `--dry-run` prints `would run <url> with sh into <prefix>` and returns; else `Http::anonymous().get(url, 256 KiB)`, write into `tempfile::tempfile()` (unnamed, nothing left behind), rewind, note `updating skillcask X -> Y with <url>`, `Command::new("sh").arg("-s").stdin(file).env("SKILLCASK_INSTALL_DIR", prefix).env("SKILLCASK_NO_MODIFY_PATH", "1").exec()`; a returned error is exit 5.
- [ ] **Step 3:** `main.rs`: `mod self_update;`, `Cmd::SelfUpdate { #[arg(long)] dry_run: bool }` with a doc line, handled next to `SelfCheck`, listed in the `unreachable!` arm.

### Task 4: integration tests

**Files:**
- Modify: `tests/common/mod.rs` (`pub bin: Option<PathBuf>` on `Project`, used by `command`)
- Create: `tests/self_update.rs`

- [ ] Up to date (cask = running version) → exit 0, `is the latest`, no request for the installer.
- [ ] Newer, test binary in `target/` → exit 1, hint names the releases page; `--dry-run` the same.
- [ ] Unix: copy the binary to `<home>/.cargo/bin/skillcask`, write the receipt in `<home>/.config/skillcask/`, serve an installer `printf '%s %s\n' "$SKILLCASK_INSTALL_DIR" "$SKILLCASK_NO_MODIFY_PATH" > "$HOME/ran"`; `self-update` exits 0 and `ran` holds `<home>/.cargo 1`; `--dry-run` writes no `ran` and requests nothing but the cask; an installer exiting 7 makes `self-update` exit 7 (exec passes it through); 404 → exit 3.
- [ ] Same copy plus `.crates2.json` → exit 1, hint `cargo install --locked skillcask`.
- [ ] `SKILLCASK_SELF_UPDATE_URL` with `http:` → exit 3, refusing non-HTTPS.

### Task 5: docs and checks

- [ ] README "### Update": `skillcask self-update` first, then the per-method commands.
- [ ] `cargo fmt --check`, `cargo clippy --all-targets --locked -- -D warnings`, `cargo test --locked`.
- [ ] Manual: real installer install on macOS, `SKILLCASK_SELF_CHECK_URL` pointing at a cask with a newer existing tag is not possible before the release; check `--dry-run` on the real install, and the exec path through the integration test.
- [ ] Commit per task (Conventional Commits), push the branch, open the PR.
