mod common;

use common::*;
use serde_json::json;

fn multi(s: &Server) {
    let zip = zipball(&[("skills/alpha/SKILL.md", &skill_md("alpha")), ("skills/beta/SKILL.md", &skill_md("beta"))]);
    s.package("acme/multi", vec![Ver { version: "1.0.0", time: Some(ago(240)), zip, extra: Some(json!(["skills/alpha", "skills/beta"])) }]);
}

fn gh_commit(sha: &str, hours: i64) -> serde_json::Value {
    json!({ "sha": sha, "commit": { "committer": { "date": ago(hours) } } })
}

fn with_github(mut p: Project, s: &Server) -> Project {
    p.env.push(("SKILLCASK_GITHUB_API".into(), s.base.clone()));
    p
}

/// `acme/tagged`: tag 1.0.0 at an old commit, also reachable as ref "1.0.0".
fn tagged(s: &Server) -> String {
    let sha = "1".repeat(40);
    s.put("/repos/acme/tagged/tags", json!([{ "name": "1.0.0", "commit": { "sha": sha } }]).to_string());
    s.put(&format!("/repos/acme/tagged/commits/{sha}"), gh_commit(&sha, 240).to_string());
    s.put("/repos/acme/tagged/commits/1.0.0", gh_commit(&sha, 240).to_string());
    s.put("/repos/acme/tagged/commits/main", gh_commit(&sha, 240).to_string());
    s.put(&format!("/repos/acme/tagged/zipball/{sha}"), zipball(&[("SKILL.md", &skill_md("tagged"))]));
    sha
}

#[test]
fn dropping_the_skill_selection_is_drift() {
    let s = Server::start();
    multi(&s);
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/multi\" = { version = \"^1.0\", skills = [\"beta\"] }\n");
    p.ok(&["install"]);
    let lock = p.read("skills.lock");
    assert!(lock.contains("selected = [\"beta\"]\n"), "{lock}");

    p.manifest(&s, "\"acme/multi\" = \"^1.0\"\n");
    let out = p.expect(&["install", "--frozen"], 1);
    assert!(out.contains("acme/multi: skill selection changed"), "{out}");
    assert!(p.expect(&["status"], 1).contains("skill selection changed"));
    p.ok(&["install"]);
    assert!(p.exists(".agents/skills/alpha") && p.exists(".agents/skills/beta"));
    assert!(!p.read("skills.lock").contains("selected"));
    p.ok(&["install", "--frozen"]);

    // A lock written before `selected` existed: absent means all, unless skills.toml selects.
    p.manifest(&s, "\"acme/multi\" = { version = \"^1.0\", skills = [\"beta\"] }\n");
    p.ok(&["install"]);
    let old = lock.replace("selected = [\"beta\"]\n", "");
    p.write("skills.lock", &old);
    p.ok(&["install", "--frozen"]);
    p.ok(&["status"]);
    assert_eq!(p.read("skills.lock"), old, "a frozen install writes nothing");
    p.ok(&["install"]);
    assert_eq!(p.read("skills.lock"), lock, "the first install adds the new keys");
}

#[test]
fn a_changed_repository_url_is_drift() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    p.ok(&["install"]);
    p.write("skills.toml", &p.read("skills.toml").replace("/packages.json", "/moved/packages.json"));
    let out = p.expect(&["install", "--frozen"], 1);
    assert!(out.contains("acme/one: repository changed"), "{out}");
    assert!(p.expect(&["status"], 1).contains("repository changed"));
}

#[test]
fn github_version_to_ref_with_the_same_string_is_drift() {
    let s = Server::start();
    tagged(&s);
    let p = with_github(Project::new(&s), &s);
    p.manifest(&s, "\"acme/tagged\" = { github = true, version = \"1.0.0\" }\n");
    p.ok(&["install"]);
    let lock = p.read("skills.lock");
    assert!(lock.contains("constraint = \"1.0.0\"\nref = false\n"), "{lock}");

    p.manifest(&s, "\"acme/tagged\" = { github = true, ref = \"1.0.0\" }\n");
    let out = p.expect(&["install", "--frozen"], 1);
    assert!(out.contains("acme/tagged: changed from version to ref"), "{out}");
    assert!(p.expect(&["status"], 1).contains("changed from version to ref"));
    p.ok(&["install"]);
    assert!(p.read("skills.lock").contains("ref = true\n"));
    p.ok(&["install", "--frozen"]);

    // A lock without the key does not fail a frozen install.
    p.write("skills.lock", &p.read("skills.lock").replace("ref = true\n", ""));
    p.ok(&["install", "--frozen"]);
}

#[test]
fn status_reports_every_drift_reason() {
    let s = Server::start();
    multi(&s);
    s.simple("acme/one", "1.0.0", "one");
    s.simple("acme/two", "1.0.0", "two");
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/multi\" = { version = \"^1.0\", skills = [\"beta\"] }\n\"acme/one\" = \"^1.0\"\n");
    p.ok(&["install"]);
    p.ok(&["status"]);

    p.manifest(&s, "\"acme/multi\" = \"^1.0\"\n\"acme/one\" = { version = \"^1.0\", rename = { one = \"x\" } }\n");
    let out = p.expect(&["status"], 1);
    assert!(out.contains("skill selection changed") && out.contains("rename changed") && out.contains("2 problem(s)"), "{out}");

    let q = Project::new(&s);
    q.manifest(&s, "\"acme/one\" = \"^1.0\"\n\"acme/two\" = \"^1.0\"\n");
    q.ok(&["install"]);
    q.write("skills.lock", &q.read("skills.lock").replace("name = \"two\"", "name = \"one\""));
    let out = q.expect(&["status"], 1);
    assert!(out.contains("skill \"one\" is provided by both acme/one and acme/two"), "{out}");
}

#[test]
fn another_github_api_base_is_not_drift() {
    let s = Server::start();
    tagged(&s);
    let p = with_github(Project::new(&s), &s);
    p.manifest(&s, "\"acme/tagged\" = { github = true, version = \"^1.0\" }\n");
    p.ok(&["install"]);
    let mut ci = clone_of(&p, &s);
    ci.env.push(("SKILLCASK_GITHUB_API".into(), format!("{}/api/v3", s.base)));
    ci.ok(&["install", "--frozen"]);
    ci.ok(&["status"]);
}
