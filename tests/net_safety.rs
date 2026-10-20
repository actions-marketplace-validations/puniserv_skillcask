mod common;

use common::*;
use serde_json::json;

fn gh_commit(sha: &str, hours: i64) -> serde_json::Value {
    json!({ "sha": sha, "commit": { "committer": { "date": ago(hours) } } })
}

fn with_github(mut p: Project, s: &Server) -> Project {
    p.env.push(("SKILLCASK_GITHUB_API".into(), s.base.clone()));
    p
}

#[test]
fn duplicate_tags_keep_the_first_one() {
    let s = Server::start();
    let (old, new) = ("1".repeat(40), "2".repeat(40));
    s.put(
        "/repos/acme/dup/tags",
        json!([{ "name": "v1.0.0", "commit": { "sha": old } }, { "name": "1.0.0", "commit": { "sha": new } }]).to_string(),
    );
    s.put(&format!("/repos/acme/dup/commits/{old}"), gh_commit(&old, 240).to_string());
    s.put(&format!("/repos/acme/dup/commits/{new}"), gh_commit(&new, 1).to_string());
    s.put(&format!("/repos/acme/dup/zipball/{old}"), zipball(&[("SKILL.md", &skill_md("dup"))]));
    s.put(&format!("/repos/acme/dup/zipball/{new}"), zipball(&[("SKILL.md", &skill_md("dup"))]));
    let p = with_github(Project::new(&s), &s);
    p.manifest(&s, "");
    p.ok(&["add", "github:acme/dup"]);
    let lock = p.read("skills.lock");
    assert!(lock.contains(&format!("zipball/{old}")) && lock.contains("version = \"v1.0.0\""), "{lock}");
}
