//! GitHub repositories as a skill source: semver tags as versions, or a branch, tag or commit
//! pinned to its sha. Skills are found by their `SKILL.md`, see `discover`.

use jiff::{RoundMode, SignedDuration, Timestamp, TimestampRound, Unit};
use serde_json::Value;

use crate::bail;
use crate::error::{Error, MANIFEST, NETWORK, Result};
use crate::http::Http;
use crate::lock::Dist;
use crate::manifest::{GitHub, Repository, SkillReq};
use crate::registry::{self, Candidate};
use crate::skill::{FileEntry, SKILL_MD};
use crate::version::{Constraint, Version};

const API: &str = "https://api.github.com";
const TAG_PAGES: usize = 10;

/// `SKILLCASK_GITHUB_API` points at GitHub Enterprise (`https://ghe.example.com/api/v3`) or a test server.
pub fn api() -> String {
    std::env::var("SKILLCASK_GITHUB_API").unwrap_or_else(|_| API.into()).trim_end_matches('/').to_string()
}

pub fn repository(name: &str) -> Repository {
    Repository { name: "github".into(), url: format!("{}/repos/{name}", api()) }
}

pub fn is_github(locked_repository: &str) -> bool {
    locked_repository.starts_with(&format!("{}/repos/", api()))
}

pub fn is_sha(r: &str) -> bool {
    r.len() == 40 && r.bytes().all(|b| b.is_ascii_hexdigit())
}

fn get(http: &Http, name: &str, path: &str) -> Result<Value> {
    let url = format!("{}{path}", repository(name).url);
    http.get_json(&url)?.ok_or_else(|| {
        // GitHub answers 404, not 401, for a private repository read without a token.
        let hint = if http.has_credential(&url) { "" } else { "; private repositories need GITHUB_TOKEN" };
        Error::new(MANIFEST, format!("GitHub: {name}: {path:?} not found (no such repository, ref or tag?{hint})"))
    })
}

fn commit_of(v: &Value, name: &str) -> Result<(String, Timestamp)> {
    let sha = v.get("sha").and_then(Value::as_str).filter(|s| is_sha(s));
    let date = v.pointer("/commit/committer/date").and_then(Value::as_str).and_then(|d| d.parse().ok());
    match (sha, date) {
        (Some(s), Some(d)) => Ok((s.to_ascii_lowercase(), d)),
        _ => bail!(NETWORK, "GitHub: {name}: unexpected commit response"),
    }
}

fn commit(http: &Http, name: &str, r: &str) -> Result<(String, Timestamp)> {
    commit_of(&get(http, name, &format!("/commits/{r}"))?, name)
}

fn candidate(name: &str, version: String, parsed: Version, sha: &str, time: Option<Timestamp>) -> Candidate {
    Candidate {
        name: name.to_string(),
        version,
        parsed,
        time,
        dist: Dist { kind: "zip".into(), url: format!("{}/zipball/{sha}", repository(name).url), reference: Some(sha.to_string()) },
        dist_shasum: None,
        // Empty: the skills are discovered in the archive.
        skill_paths: Vec::new(),
    }
}

/// Tags that parse as versions, newest first, without release times.
pub fn tags(http: &Http, name: &str) -> Result<Vec<Candidate>> {
    let mut out = Vec::new();
    let mut full = false;
    for page in 1..=TAG_PAGES {
        let v = get(http, name, &format!("/tags?per_page=100&page={page}"))?;
        let list = v.as_array().ok_or_else(|| Error::new(NETWORK, format!("GitHub: {name}: unexpected tags response")))?;
        for t in list {
            let (Some(tag), Some(sha)) = (t.get("name").and_then(Value::as_str), t.pointer("/commit/sha").and_then(Value::as_str)) else {
                continue;
            };
            // Keep the first of tags naming the same version: release times are fetched for one only.
            if let Some(parsed) = Version::parse(tag).filter(|v| is_sha(sha) && !out.iter().any(|c: &Candidate| &c.parsed == v)) {
                out.push(candidate(name, tag.to_string(), parsed, &sha.to_ascii_lowercase(), None));
            }
        }
        full = list.len() >= 100;
        if !full {
            break;
        }
    }
    if full {
        eprintln!("warning: {name}: more than {} tags; only the first {} were read", TAG_PAGES * 100, TAG_PAGES * 100);
    }
    out.sort_by(|a, b| b.parsed.cmp(&a.parsed));
    Ok(out)
}

pub fn resolve(http: &Http, req: &SkillReq, min_age: SignedDuration, now: Timestamp) -> Result<Candidate> {
    let name = &req.name;
    let cutoff = now.checked_sub(min_age).unwrap_or(Timestamp::MIN);
    match req.github {
        Some(GitHub::Tags) => {
            let mut cands = tags(http, name)?;
            if cands.is_empty() {
                bail!(MANIFEST, "{name}: the repository has no version tags; use `ref` instead of `version`");
            }
            let c = Constraint::parse(&req.constraint).map_err(|e| Error::new(MANIFEST, format!("{name}: {e}")))?;
            // Release time is one request per tag: newest first, stop at the first one past the cooldown.
            // Older matching tags keep no time, but `select` never reaches them.
            for x in cands.iter_mut().filter(|x| c.allows(&x.parsed)) {
                let t = commit(http, name, x.dist.reference.as_deref().expect("set by candidate"))?.1;
                x.time = Some(t);
                if t <= cutoff {
                    break;
                }
            }
            registry::select(&cands, name, &req.constraint, min_age, now)
        }
        Some(GitHub::Ref) => {
            let r = &req.constraint;
            let (mut sha, mut time) = commit(http, name, r)?;
            if time > cutoff {
                let eligible = time.checked_add(min_age).unwrap_or(Timestamp::MAX).round(jiff::Unit::Second).unwrap_or(time);
                if is_sha(r) {
                    bail!(
                        MANIFEST,
                        "{name}: commit {r} is newer than policy.min-release-age ({min_age:#}); it becomes eligible at {eligible}"
                    );
                }
                let until = cutoff.round(TimestampRound::new().smallest(Unit::Second).mode(RoundMode::Trunc)).unwrap_or(cutoff);
                let older = get(http, name, &format!("/commits?sha={r}&per_page=1&until={until}"))?;
                let none = || {
                    Error::new(
                        MANIFEST,
                        format!(
                            "{name}: every commit on {r:?} is newer than policy.min-release-age ({min_age:#}); the newest becomes eligible at {eligible}"
                        ),
                    )
                };
                let first = older.as_array().and_then(|a| a.first()).ok_or_else(none)?;
                (sha, time) = commit_of(first, name)?;
                // Do not trust `until` alone: the API (or a proxy) may ignore it.
                if time > cutoff {
                    return Err(none());
                }
                eprintln!("note: {name}: newer commits on {r:?} are within policy.min-release-age; using {}", &sha[..12]);
            }
            let parsed = Version::parse("0.0.0").expect("valid");
            Ok(candidate(name, sha[..12].to_string(), parsed, &sha, Some(time)))
        }
        None => unreachable!("only GitHub entries are resolved here"),
    }
}

/// (newest within the constraint, newest overall) for `outdated`; cooldown is not applied.
pub fn newest(http: &Http, req: &SkillReq) -> Result<(Option<String>, Option<String>)> {
    if req.github == Some(GitHub::Ref) {
        let head = commit(http, &req.name, &req.constraint)?.0[..12].to_string();
        return Ok((Some(head.clone()), Some(head)));
    }
    let cands = tags(http, &req.name)?;
    let c = Constraint::parse(&req.constraint).map_err(|e| Error::new(MANIFEST, format!("{}: {e}", req.name)))?;
    let v = |x: Option<&Candidate>| x.map(|x| x.version.clone());
    Ok((v(registry::newest(&cands, Some(&c))), v(registry::newest(&cands, None))))
}

/// Paths of `SKILL.md` files in a repository archive, skipping those nested in another skill.
pub fn discover(entries: &[FileEntry]) -> Vec<String> {
    let mut dirs: Vec<&str> =
        entries.iter().filter_map(|e| if e.path == SKILL_MD { Some("") } else { e.path.strip_suffix(&format!("/{SKILL_MD}")) }).collect();
    dirs.sort();
    let mut out: Vec<&str> = Vec::new();
    for d in dirs {
        if !out.iter().any(|o| o.is_empty() || d.starts_with(&format!("{o}/"))) {
            out.push(d);
        }
    }
    out.into_iter().map(|d| if d.is_empty() { SKILL_MD.to_string() } else { format!("{d}/{SKILL_MD}") }).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn discovers_outermost_skills() {
        let e = |p: &str| FileEntry::new(p.into(), false, b"");
        let found = discover(&[
            e("README.md"),
            e("skills/b/SKILL.md"),
            e("skills/b/examples/x/SKILL.md"),
            e("skills/a/SKILL.md"),
            e("a/SKILL.mdx"),
        ]);
        assert_eq!(found, ["skills/a/SKILL.md", "skills/b/SKILL.md"]);
        assert_eq!(discover(&[e("SKILL.md"), e("sub/SKILL.md")]), ["SKILL.md"]);
        assert!(is_sha(&"a".repeat(40)) && !is_sha("main") && !is_sha(&"g".repeat(40)));
    }
}
