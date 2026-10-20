//! `skills.toml`: read with declaration order preserved, edited in place so comments survive.

use std::path::Path;

use jiff::SignedDuration;
use toml_edit::{DocumentMut, InlineTable, Item, Value};

use crate::bail;
use crate::error::{Context, MANIFEST, Result};

pub const FILE: &str = "skills.toml";
pub const PACKAGIST_URL: &str = "https://repo.packagist.org";
pub const DEFAULT_TARGETS: [&str; 2] = [".claude/skills", ".junie/skills"];
pub const DEFAULT_LOCAL: &str = ".skills";

pub const TEMPLATE: &str = r#"# skillcask manifest. Lock: skills.lock (generated, commit both).

[repositories]
# name = { type = "composer", url = "https://example.com/packages.json" }

[skills]
# "vendor/name" = "^1.0"
# "owner/repo" = { github = true, skills = ["name"] }   # GitHub, default branch

[agents]
targets = [".claude/skills", ".junie/skills"]
local = ".skills"   # project skills, linked into .agents/skills

[policy]
min-release-age = "3d"
allow-ranges = true
packagist = true
"#;

pub const GLOBAL_TEMPLATE: &str = r#"# skillcask global manifest: personal skills in ~/.agents/skills. Lock: skills.lock.

[repositories]
# name = { type = "composer", url = "https://example.com/packages.json" }

[skills]
# "vendor/name" = "^1.0"
# "owner/repo" = { github = true, skills = ["name"] }   # GitHub, default branch

[agents]
targets = [".claude/skills", ".junie/skills"]

[policy]
min-release-age = "3d"
allow-ranges = true
packagist = true
"#;

pub fn template(global: bool) -> &'static str {
    if global { GLOBAL_TEMPLATE } else { TEMPLATE }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Repository {
    pub name: String,
    pub url: String,
}

/// A GitHub source: `constraint` is a version constraint over tags, or a branch, tag or commit.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum GitHub {
    Tags,
    Ref,
}

/// The `ref` of a GitHub entry without one: the default branch.
pub const DEFAULT_REF: &str = "HEAD";

#[derive(Clone, Debug, PartialEq)]
pub struct SkillReq {
    pub name: String,
    pub constraint: String,
    pub repository: Option<String>,
    pub skills: Option<Vec<String>>,
    pub github: Option<GitHub>,
}

#[derive(Clone, Debug)]
pub struct Policy {
    pub min_release_age: SignedDuration,
    pub allow_ranges: bool,
    pub packagist: bool,
}

#[derive(Clone, Debug)]
pub struct Manifest {
    /// Declared order, then the implicit Packagist unless `policy.packagist = false`.
    pub repositories: Vec<Repository>,
    pub skills: Vec<SkillReq>,
    pub targets: Vec<String>,
    /// Project skills, linked into the store (`[agents] local`, default `.skills`).
    pub local: String,
    pub policy: Policy,
}

impl Manifest {
    pub fn load(dir: &Path, global: bool) -> Result<Manifest> {
        let path = dir.join(FILE);
        if !path.exists() {
            bail!(MANIFEST, "{FILE} not found; run `skillcask init{}`", if global { " --global" } else { "" });
        }
        parse(&std::fs::read_to_string(&path)?, global)
    }

    pub fn repository(&self, name: &str) -> Option<&Repository> {
        self.repositories.iter().find(|r| r.name == name)
    }

    pub fn skill(&self, name: &str) -> Option<&SkillReq> {
        self.skills.iter().find(|s| s.name == name)
    }
}

fn bad(what: impl std::fmt::Display) -> crate::error::Error {
    crate::error::Error::new(MANIFEST, format!("{FILE}: {what}"))
}

pub fn parse(text: &str, global: bool) -> Result<Manifest> {
    let doc: DocumentMut = text.parse().map_err(bad)?;

    let mut repositories = Vec::new();
    if let Some(t) = doc.get("repositories").and_then(Item::as_table_like) {
        for (name, item) in t.iter() {
            let r = item.as_table_like().ok_or_else(|| bad(format!("repository {name} must be a table")))?;
            let kind = r.get("type").and_then(Item::as_str).unwrap_or("composer");
            if kind != "composer" {
                return Err(bad(format!("repository {name}: type {kind:?} is not supported, only \"composer\"")));
            }
            let url = r.get("url").and_then(Item::as_str).ok_or_else(|| bad(format!("repository {name}: missing url")))?;
            if !url.starts_with("https://") {
                return Err(bad(format!("repository {name}: only https:// URLs are allowed")));
            }
            repositories.push(Repository { name: name.to_string(), url: url.to_string() });
        }
    }

    let policy = doc.get("policy").and_then(Item::as_table_like);
    let get = |k: &str| policy.and_then(|p| p.get(k));
    let min_release_age = match get("min-release-age") {
        None => SignedDuration::from_hours(72),
        Some(i) => match (i.as_str(), i.as_integer()) {
            (Some(s), _) => parse_age(s)?,
            (_, Some(0)) => SignedDuration::ZERO,
            _ => return Err(bad("policy.min-release-age must be a string such as \"3d\"")),
        },
    };
    let flag = |k: &str| -> Result<bool> {
        match get(k) {
            None => Ok(true),
            Some(i) => i.as_bool().ok_or_else(|| bad(format!("policy.{k} must be true or false"))),
        }
    };
    let policy = Policy { min_release_age, allow_ranges: flag("allow-ranges")?, packagist: flag("packagist")? };
    if policy.packagist && !repositories.iter().any(|r| r.name == "packagist") {
        repositories.push(Repository { name: "packagist".into(), url: PACKAGIST_URL.into() });
    }

    let mut skills = Vec::new();
    if let Some(t) = doc.get("skills").and_then(Item::as_table_like) {
        for (name, item) in t.iter() {
            if !valid_package_name(name) {
                return Err(bad(format!("{name:?} is not a valid package name (vendor/name, lowercase)")));
            }
            let req = if let Some(c) = item.as_str() {
                SkillReq { name: name.into(), constraint: c.into(), repository: None, skills: None, github: None }
            } else if let Some(t) = item.as_table_like() {
                let github = match t.get("github") {
                    None => false,
                    Some(i) => i.as_bool().ok_or_else(|| bad(format!("{name}: github must be true or false")))?,
                };
                let version = t.get("version").and_then(Item::as_str);
                let git_ref = t.get("ref").and_then(Item::as_str);
                let repository = t.get("repository").and_then(Item::as_str).map(String::from);
                let (constraint, github) = match (github, version, git_ref) {
                    (_, Some(_), Some(_)) => return Err(bad(format!("{name}: set either version or ref, not both"))),
                    (false, _, Some(_)) => return Err(bad(format!("{name}: ref needs github = true"))),
                    (false, None, None) => return Err(bad(format!("{name}: missing version"))),
                    (false, Some(v), None) => (v, None),
                    (true, Some(v), None) => (v, Some(GitHub::Tags)),
                    (true, None, r) => (r.unwrap_or(DEFAULT_REF), Some(GitHub::Ref)),
                };
                if let Some(r) = &repository {
                    if github.is_some() {
                        return Err(bad(format!("{name}: repository and github = true cannot be combined")));
                    }
                    if !repositories.iter().any(|x| &x.name == r) {
                        return Err(bad(format!("{name}: unknown repository {r:?}")));
                    }
                }
                let skills = match t.get("skills") {
                    None => None,
                    Some(i) => Some(string_array(i).ok_or_else(|| bad(format!("{name}: skills must be a list of names")))?),
                };
                SkillReq { name: name.into(), constraint: constraint.into(), repository, skills, github }
            } else {
                return Err(bad(format!("{name}: expected a version string or a table")));
            };
            check_constraint(&req, &policy).map_err(|e| bad(format!("{name}: {e}")))?;
            skills.push(req);
        }
    }

    let agents = doc.get("agents").and_then(Item::as_table_like);
    let local = match agents.and_then(|a| a.get("local")) {
        Some(_) if global => {
            return Err(bad("agents.local is not supported with --global; personal skills go straight into ~/.agents/skills"));
        }
        None => DEFAULT_LOCAL.to_string(),
        Some(i) => i.as_str().ok_or_else(|| bad("agents.local must be a path"))?.trim_end_matches('/').to_string(),
    };
    let targets = match agents.and_then(|a| a.get("targets")) {
        None => DEFAULT_TARGETS.iter().map(|s| s.to_string()).collect(),
        Some(i) => string_array(i).ok_or_else(|| bad("agents.targets must be a list of paths"))?,
    };
    for t in targets.iter().chain([&local]) {
        let p = Path::new(t);
        if p.is_absolute() || p.components().any(|c| !matches!(c, std::path::Component::Normal(_))) || t.is_empty() {
            return Err(bad(format!("agents: {t:?} must be a relative path inside the project")));
        }
        if p == Path::new(crate::project::STORE) {
            return Err(bad(format!("agents: {t:?} is the store itself")));
        }
    }

    if !global && targets.contains(&local) {
        return Err(bad(format!("agents.local {local:?} cannot also be a target")));
    }

    Ok(Manifest { repositories, skills, targets, local, policy })
}

/// The version constraint, or for a GitHub `ref` its syntax; `allow-ranges = false` also forbids
/// branches, since they move like ranges do.
pub fn check_constraint(req: &SkillReq, policy: &Policy) -> std::result::Result<(), String> {
    let c = &req.constraint;
    if req.github == Some(GitHub::Ref) {
        // The ref ends up in a GitHub API URL path, so no escaping is needed for these characters.
        let ok = !c.is_empty()
            && !c.starts_with(['-', '/'])
            && !c.ends_with('/')
            && !c.contains("..")
            && !c.contains("//")
            && c.chars().all(|ch| ch.is_ascii_alphanumeric() || "._/-".contains(ch));
        if !ok {
            return Err(format!("invalid ref {c:?}"));
        }
        if !policy.allow_ranges && !crate::github::is_sha(c) {
            return Err(format!("policy.allow-ranges = false requires ref to be a full commit sha, got {c:?}"));
        }
        return Ok(());
    }
    crate::version::Constraint::parse(c)?;
    if !policy.allow_ranges && !crate::version::is_exact(c) {
        return Err(format!("policy.allow-ranges = false requires an exact version, got {c:?}"));
    }
    Ok(())
}

fn string_array(i: &Item) -> Option<Vec<String>> {
    i.as_array()?.iter().map(|v| v.as_str().map(String::from)).collect()
}

/// Composer's package name rule.
pub fn valid_package_name(n: &str) -> bool {
    let Some((v, p)) = n.split_once('/') else { return false };
    let part = |s: &str| {
        !s.is_empty()
            && s.starts_with(|c: char| c.is_ascii_lowercase() || c.is_ascii_digit())
            && s.ends_with(|c: char| c.is_ascii_lowercase() || c.is_ascii_digit())
            && s.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || "_.-".contains(c))
            && !s.contains("..")
    };
    part(v) && part(p)
}

/// `"3d"`, `"12h"`, `"30m"`, `"1w"`, `"90s"`, `"0"`.
pub fn parse_age(s: &str) -> Result<SignedDuration> {
    let s = s.trim();
    if s == "0" {
        return Ok(SignedDuration::ZERO);
    }
    let (num, unit) = s.split_at(s.find(|c: char| !c.is_ascii_digit()).unwrap_or(s.len()));
    let n: i64 = num.parse().map_err(|_| bad(format!("invalid duration {s:?}")))?;
    let secs = match unit {
        "s" => 1,
        "m" => 60,
        "h" => 3600,
        "d" => 86400,
        "w" => 7 * 86400,
        _ => return Err(bad(format!("invalid duration {s:?}, use s, m, h, d or w"))),
    };
    Ok(SignedDuration::from_secs(n * secs))
}

fn edit(root: &Path, global: bool, f: impl FnOnce(&mut DocumentMut)) -> Result<()> {
    let path = root.join(FILE);
    let text = std::fs::read_to_string(&path).ctx(FILE)?;
    let mut doc: DocumentMut = text.parse().map_err(bad)?;
    f(&mut doc);
    parse(&doc.to_string(), global)?;
    std::fs::write(&path, doc.to_string())?;
    Ok(())
}

pub fn write_skill(root: &Path, global: bool, req: &SkillReq) -> Result<()> {
    edit(root, global, |doc| {
        let skills = doc.entry("skills").or_insert(toml_edit::table());
        let item = if req.repository.is_none() && req.skills.is_none() && req.github.is_none() {
            toml_edit::value(req.constraint.as_str())
        } else {
            let mut t = InlineTable::new();
            match req.github {
                None => {
                    t.insert("version", req.constraint.as_str().into());
                }
                Some(g) => {
                    t.insert("github", true.into());
                    if g == GitHub::Tags {
                        t.insert("version", req.constraint.as_str().into());
                    } else if req.constraint != DEFAULT_REF {
                        t.insert("ref", req.constraint.as_str().into());
                    }
                }
            }
            if let Some(r) = &req.repository {
                t.insert("repository", r.as_str().into());
            }
            if let Some(s) = &req.skills {
                t.insert("skills", Value::Array(s.iter().map(String::as_str).collect()));
            }
            Item::Value(Value::InlineTable(t))
        };
        skills[req.name.as_str()] = item;
    })
}

pub fn remove_skills(root: &Path, global: bool, names: &[String]) -> Result<()> {
    edit(root, global, |doc| {
        if let Some(t) = doc.get_mut("skills").and_then(Item::as_table_like_mut) {
            for n in names {
                t.remove(n);
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_spec_example() {
        let m = parse(
            r#"
[repositories]
acme = { type = "composer", url = "https://git.example.com/packages.json" }

[skills]
"netresearch/agent-jira-skill" = "^2.0"
"acme/agents-md" = { version = "^1.0", repository = "acme" }
"acme/review" = { version = "1.4.2", repository = "acme", skills = ["review"] }

[agents]
targets = [".claude/skills"]

[policy]
min-release-age = "12h"
"#,
            false,
        )
        .unwrap();
        assert_eq!(m.repositories.iter().map(|r| r.name.as_str()).collect::<Vec<_>>(), ["acme", "packagist"]);
        assert_eq!(m.skills.len(), 3);
        assert_eq!(m.skills[2].skills.as_deref(), Some(&["review".to_string()][..]));
        assert_eq!(m.targets, [".claude/skills"]);
        assert_eq!(m.policy.min_release_age, SignedDuration::from_hours(12));
    }

    #[test]
    fn defaults_and_rejections() {
        let m = parse(TEMPLATE, false).unwrap();
        assert!(parse(GLOBAL_TEMPLATE, true).is_ok());
        assert!(parse("[agents]\nlocal = \".skills\"", true).is_err());
        assert_eq!(m.policy.min_release_age, SignedDuration::from_hours(72));
        assert_eq!(m.targets, DEFAULT_TARGETS);
        assert!(parse("[repositories]\nx = { url = \"http://a\" }", false).is_err());
        assert!(parse("[skills]\n\"Acme/X\" = \"1.0\"", false).is_err());
        assert!(parse("[skills]\n\"a/b\" = { version = \"1\", repository = \"nope\" }", false).is_err());
        assert!(parse("[policy]\nallow-ranges = false\n[skills]\n\"a/b\" = \"^1.0\"", false).is_err());
        assert!(parse("[policy]\nallow-ranges = false\n[skills]\n\"a/b\" = \"1.0.3\"", false).is_ok());
        assert!(parse("[agents]\ntargets = [\"../x\"]", false).is_err());
        assert!(parse("[policy]\npackagist = false", false).unwrap().repositories.is_empty());
        let gh = |entry: &str| parse(&format!("[repositories]\nr = {{ url = \"https://r\" }}\n[skills]\n\"a/b\" = {entry}"), false);
        assert!(gh("{ github = true, ref = \"main\" }").is_ok());
        assert!(gh("{ github = true, version = \"^1.0\", ref = \"main\" }").is_err());
        assert!(gh("{ ref = \"main\" }").is_err());
        assert!(gh("{ github = true, repository = \"r\" }").is_err());
        for evil in ["../x", "a b", "-x", "a?b", "a//b", "x/"] {
            assert!(gh(&format!("{{ github = true, ref = {evil:?} }}")).is_err(), "{evil}");
        }
        let strict = |entry: &str| parse(&format!("[policy]\nallow-ranges = false\n[skills]\n\"a/b\" = {entry}"), false);
        assert!(strict("{ github = true }").is_err());
        assert!(strict(&format!("{{ github = true, ref = \"{}\" }}", "ab".repeat(20))).is_ok());
        assert_eq!(parse_age("0").unwrap(), SignedDuration::ZERO);
        assert!(parse_age("3y").is_err());
    }

    #[test]
    fn edits_keep_comments() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join(FILE), TEMPLATE).unwrap();
        let req =
            SkillReq { name: "a/b".into(), constraint: "^1.0".into(), repository: None, skills: Some(vec!["x".into()]), github: None };
        write_skill(dir.path(), false, &req).unwrap();
        let text = std::fs::read_to_string(dir.path().join(FILE)).unwrap();
        assert!(text.contains("# skillcask manifest"));
        assert_eq!(parse(&text, false).unwrap().skills, std::slice::from_ref(&req));
        for (constraint, github, line) in [
            (DEFAULT_REF, GitHub::Ref, r#""a/b" = { github = true }"#),
            ("feature/x", GitHub::Ref, r#""a/b" = { github = true, ref = "feature/x" }"#),
            ("^1.3", GitHub::Tags, r#""a/b" = { github = true, version = "^1.3" }"#),
        ] {
            let gh = SkillReq { constraint: constraint.into(), skills: None, github: Some(github), ..req.clone() };
            write_skill(dir.path(), false, &gh).unwrap();
            let text = std::fs::read_to_string(dir.path().join(FILE)).unwrap();
            assert!(text.contains(line), "{text}");
            assert_eq!(parse(&text, false).unwrap().skills, [gh]);
        }
        remove_skills(dir.path(), false, &["a/b".into()]).unwrap();
        assert!(parse(&std::fs::read_to_string(dir.path().join(FILE)).unwrap(), false).unwrap().skills.is_empty());
    }
}
