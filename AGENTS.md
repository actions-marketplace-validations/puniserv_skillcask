# skillcask

Lockfile-first package manager for agent skills, shipped as one Rust binary. Design, non-goals and
numbered decisions (D1, D2, …) live in `docs/specs/2026-10-19-skillcask-v1.md`: read it before
changing how the manifest, lock, install or publish behave, and record a new decision there in the
same change.

## Checks

Run what CI runs before every commit:

```sh
cargo fmt --check
cargo clippy --all-targets --locked -- -D warnings
cargo test --locked
```

`cargo test --locked --test cli -- --ignored` runs end-to-end against live Packagist; run it after
touching registry or HTTP code.

CI tests Linux, macOS and Windows. Paths, symlinks and exec bits must work on all three.

## Invariants

- Package content is data only: skillcask never runs scripts, hooks or plugins from a package.
- `install` installs exactly what the lock pins and fails on any hash mismatch.
- No telemetry.
- The repository is public: code, docs and commit messages name only public projects and services.

## Commits

Conventional Commits with a lowercase subject that states the outcome, e.g.
`fix: refuse symlinked project dirs and harden add, gitignore and CLI errors`.

## Release

1. Bump `version` in `Cargo.toml`, run `cargo build` to update `Cargo.lock`, commit
   `chore: release X.Y.Z`, push.
2. `git tag vX.Y.Z && git push origin vX.Y.Z`. `release.yml` builds all targets and publishes the
   GitHub Release, Homebrew formula and npm package.
3. `cargo publish --locked` from the tag (manual).
4. Edit the GitHub Release in the browser, tick "Publish this Action to the GitHub Marketplace" and
   save (manual: GitHub has no API for it, and releases made by `release.yml` are not listed).

`release.yml` comes from `dist generate`, but it is hand-edited; re-apply the edits after
regenerating:

- `publish-npm` uses npm trusted publishing: `id-token: write`, an exact npm >= 11.5.1 at least
  3 days old, no `GH_TOKEN`, and no `registry-url` in `setup-node` (it injects a placeholder
  `NODE_AUTH_TOKEN` that breaks OIDC with E404).
- Supply chain: every action pinned to a commit sha, the dist installer checked against a pinned
  sha256, and `GH_TOKEN: ""` on the steps that install tools.
