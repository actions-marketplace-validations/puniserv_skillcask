# Spec: dependencies between skills

Date: 2026-10-20. Status: draft.

## Problem

Some skills only work together with others. A merge request skill that tells the agent to run a
security review and to write the description with a PR skill is broken when either of those is
missing, yet today every consumer has to know that and add all three to `skills.toml` by hand.
v1 lists dependencies as a non-goal and ignores Composer `require`.

## Goals

1. A skill declares the skills it needs in its own `SKILL.md`; `add`, `install` and `update`
   resolve, lock and install them with the same verification as direct entries.
2. A dependency never widens what the consumer trusts: it comes only from the consumer's
   repositories, or from GitHub only when the consumer opted in.
3. `install --frozen` still installs exactly the lock, offline except for dists.

## Non-goals

- Composer `require`: existing skill packages put `php`, `ext-*` and Composer plugins there.
  It stays ignored.
- Depending on one skill of a Composer package (`vendor/name/skill`). `publish` makes one package
  per skill, so the package is the unit; GitHub repositories, which ship many skills, get
  `/skill`.
- Several versions of one package side by side. Skills have no namespaces; one directory per name.
- Backtracking. One pass picks the highest version that satisfies every constraint on a package.
- `outdated` for dependencies.

## Declaring

Top-level `requires:` in the frontmatter of `SKILL.md`, a one-level block mapping:

```yaml
---
name: gitlab-branch-mr
version: 1.2.0
requires:
  acme/gr-security-ssdlc-review: ^1.0
  github:mattpocock/skills/pr: main
---
```

- Key `vendor/name`: a Composer package, value a version constraint.
- Key `github:owner/repo[/skill]`: a GitHub repository, all its skills or one. The value follows
  `add github:`: a version constraint over tags when it parses as one, else a branch, tag or
  commit.
- Keys and values may be quoted. Anything else (a list, a nested map, an invalid name or
  constraint) is an error naming the package, version and `SKILL.md` path. `publish` checks the
  same rules, so a typo fails in the skill's own CI, not at the consumer.
- Only the skills a package installs count: with `skills = ["a"]`, the `requires:` of skill `b`
  in the same package is not read. Frontmatter is read before a rename.

## Resolving

A worklist over the manifest entries:

1. Resolve and lock each manifest entry as today.
2. Read `requires:` of every installed skill of the package; add each requirement to the package
   it names, recording the requirer.
3. For each required package: collect its constraints from all requirers and from its manifest
   entry, if any. Keep the locked version when it satisfies all of them and its source did not
   change; else pick the highest version that satisfies all of them (each checked on its own, not
   joined into one string, because `||` binds looser than `,`). None: exit 1, listing each
   requirer and its constraint.
4. Repeat for the new packages' own `requires:` until nothing changes. A cycle ends because a
   package is resolved once per run.

Sources:

- A Composer dependency is looked up like a manifest entry without `repository`: declared
  repositories in order, then Packagist when `policy.packagist` is on. Once locked, only in its
  locked repository (the dependency-confusion guard of v1). The cooldown of that repository
  applies (D15).
- A GitHub dependency needs `policy.github-requires = true` in the consumer's `skills.toml`;
  without it, exit 1 naming the requirer and the line to add. Cooldown and pinning as for
  `github = true` entries.
- Requirements on one package must agree on its kind: GitHub vs Composer, and for GitHub ref vs
  tags; two different refs are a conflict. A GitHub dependency installs the union of the skills
  its requirers name, or all of them when any requirer names none.
- A manifest entry for the same package wins on source, `skills` and `rename`; requirers add
  constraints. A requirer asking for a skill its `skills = [...]` does not select: exit 1.
- `policy.allow-ranges = false` applies to the manifest only; the lock pins exact versions anyway.

## Lock

Two keys, written only when they apply:

```toml
[[package]]
name = "acme/gitlab-branch-mr"
constraint = "^1.2"
version = "1.2.0"
requires = { "acme/gr-security-ssdlc-review" = "^1.0", "github:mattpocock/skills/pr" = "main" }
# …

[[package]]
name = "acme/gr-security-ssdlc-review"
constraint = "^1.0"
dependency = true
version = "1.3.1"
# …
```

- `requires`: the union of `requires:` of the package's installed skills, sorted. It lets
  `install`, `status` and `remove` see the graph without downloading.
- `dependency = true`: the package has no manifest entry. Its `constraint` is the distinct
  constraints of its requirers, sorted, joined with `, `, for display; drift is decided by
  checking the locked version against each requirer's constraint, not by comparing this string.
- A lock with either key is written as `version = 2`; one without stays `version = 1`, byte for
  byte as before. An older skillcask stops on `version = 2` instead of dropping dependencies it
  does not understand.
- Parsing validates `requires` keys and constraints like the frontmatter. A `dependency = true`
  package nobody requires is drift, not a parse error.

## Commands

- `add`: after the entry, resolves its dependencies; prints `added … (dependency of …)` for each
  new one. Nothing is written when any dependency fails.
- `install`: drift now also covers dependencies: a requirer that is new or changed, a dependency
  whose locked version no longer satisfies a requirer, a dependency nobody requires any more.
  Non-frozen resolves them; `--frozen` exits 1 as for manifest drift.
- `update [names]`: without names, re-resolves every package including dependencies. With names,
  the named packages (a dependency may be named) and dependencies they bring in or no longer
  satisfy.
- `remove <name>`: drops the entry and every dependency no longer required. A package still
  required by another stays as a dependency, with a note. Naming a package that is only a
  dependency: exit 1 naming its requirers.
- `status`: dependency rows show `via <requirer>`; drift reasons as for `install`.
- A name clash involving a dependency is not offered an interactive rename; the error says to add
  the dependency to `skills.toml` with `rename = { … }`, which turns it into a manifest entry.

## Security

- Dependencies come from the consumer's repositories only; GitHub needs an explicit opt-in. A
  package author cannot point a consumer at a new host.
- Every dependency is pinned and hashed in the lock and passes the cooldown, like a direct entry.
- `add` and `update` list every dependency they lock, so it shows up in the reviewed diff of
  `skills.lock`.
- No code runs; `requires:` is data.

## Testing

- Unit: `requires:` parsing (block map, quotes, comments, invalid shapes), lock round-trip with
  `requires` / `dependency` and the version switch, constraint intersection with `||`.
- Integration (local HTTPS fixture repository): transitive install and frozen reinstall; two
  requirers with a common and with an incompatible constraint (exit 1); dependency only in a
  repository the consumer did not declare (exit 1); GitHub dependency without and with the
  opt-in; `remove` of a requirer drops orphans and keeps shared ones; `skills = [...]` ignores
  `requires:` of unselected skills; cycle A → B → A; frozen drift when a requirer gains a
  dependency.
