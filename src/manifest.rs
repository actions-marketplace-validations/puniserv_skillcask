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

[agents]
targets = [".claude/skills", ".junie/skills"]
local = ".skills"   # project skills, linked into .agents/skills

[policy]
min-release-age = "3d"
allow-ranges = true
packagist = true
"#;

#[derive(Clone, Debug, PartialEq)]
pub struct Repository {
    pub name: String,
    pub url: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SkillReq {
    pub name: String,
    pub constraint: String,
    pub repository: Option<String>,
    pub skills: Option<Vec<String>>,
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
    pub fn load(root: &Path) -> Result<Manifest> {
        let path = root.join(FILE);
        if !path.exists() {
            bail!(MANIFEST, "{FILE} not found; run `skillcask init`");
        }
        parse(&std::fs::read_to_string(&path)?)
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

pub fn parse(text: &str) -> Result<Manifest> {
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
                SkillReq { name: name.into(), constraint: c.into(), repository: None, skills: None }
            } else if let Some(t) = item.as_table_like() {
                let constraint = t.get("version").and_then(Item::as_str).ok_or_else(|| bad(format!("{name}: missing version")))?;
                let repository = t.get("repository").and_then(Item::as_str).map(String::from);
                if let Some(r) = &repository
                    && !repositories.iter().any(|x| &x.name == r)
                {
                    return Err(bad(format!("{name}: unknown repository {r:?}")));
                }
                let skills = match t.get("skills") {
                    None => None,
                    Some(i) => Some(string_array(i).ok_or_else(|| bad(format!("{name}: skills must be a list of names")))?),
                };
                SkillReq { name: name.into(), constraint: constraint.into(), repository, skills }
            } else {
                return Err(bad(format!("{name}: expected a version string or a table")));
            };
            crate::version::Constraint::parse(&req.constraint).map_err(|e| bad(format!("{name}: {e}")))?;
            if !policy.allow_ranges && !crate::version::is_exact(&req.constraint) {
                return Err(bad(format!("{name}: policy.allow-ranges = false requires an exact version, got {:?}", req.constraint)));
            }
            skills.push(req);
        }
    }

    let agents = doc.get("agents").and_then(Item::as_table_like);
    let local = match agents.and_then(|a| a.get("local")) {
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

    if targets.contains(&local) {
        return Err(bad(format!("agents.local {local:?} cannot also be a target")));
    }

    Ok(Manifest { repositories, skills, targets, local, policy })
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

fn edit(root: &Path, f: impl FnOnce(&mut DocumentMut)) -> Result<()> {
    let path = root.join(FILE);
    let text = std::fs::read_to_string(&path).ctx(FILE)?;
    let mut doc: DocumentMut = text.parse().map_err(bad)?;
    f(&mut doc);
    parse(&doc.to_string())?;
    std::fs::write(&path, doc.to_string())?;
    Ok(())
}

pub fn write_skill(root: &Path, req: &SkillReq) -> Result<()> {
    edit(root, |doc| {
        let skills = doc.entry("skills").or_insert(toml_edit::table());
        let item = if req.repository.is_none() && req.skills.is_none() {
            toml_edit::value(req.constraint.as_str())
        } else {
            let mut t = InlineTable::new();
            t.insert("version", req.constraint.as_str().into());
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

pub fn remove_skills(root: &Path, names: &[String]) -> Result<()> {
    edit(root, |doc| {
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
        let m = parse(TEMPLATE).unwrap();
        assert_eq!(m.policy.min_release_age, SignedDuration::from_hours(72));
        assert_eq!(m.targets, DEFAULT_TARGETS);
        assert!(parse("[repositories]\nx = { url = \"http://a\" }").is_err());
        assert!(parse("[skills]\n\"Acme/X\" = \"1.0\"").is_err());
        assert!(parse("[skills]\n\"a/b\" = { version = \"1\", repository = \"nope\" }").is_err());
        assert!(parse("[policy]\nallow-ranges = false\n[skills]\n\"a/b\" = \"^1.0\"").is_err());
        assert!(parse("[policy]\nallow-ranges = false\n[skills]\n\"a/b\" = \"1.0.3\"").is_ok());
        assert!(parse("[agents]\ntargets = [\"../x\"]").is_err());
        assert!(parse("[policy]\npackagist = false").unwrap().repositories.is_empty());
        assert_eq!(parse_age("0").unwrap(), SignedDuration::ZERO);
        assert!(parse_age("3y").is_err());
    }

    #[test]
    fn edits_keep_comments() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join(FILE), TEMPLATE).unwrap();
        let req = SkillReq { name: "a/b".into(), constraint: "^1.0".into(), repository: None, skills: Some(vec!["x".into()]) };
        write_skill(dir.path(), &req).unwrap();
        let text = std::fs::read_to_string(dir.path().join(FILE)).unwrap();
        assert!(text.contains("# skillcask manifest"));
        assert_eq!(parse(&text).unwrap().skills, [req]);
        remove_skills(dir.path(), &["a/b".into()]).unwrap();
        assert!(parse(&std::fs::read_to_string(dir.path().join(FILE)).unwrap()).unwrap().skills.is_empty());
    }
}
