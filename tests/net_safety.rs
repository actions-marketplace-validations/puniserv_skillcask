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

fn host(s: &Server) -> String {
    s.base.trim_start_matches("https://").to_string()
}

/// Trusts the test CAs of several servers at once.
fn trust(p: &mut Project, servers: &[&Server]) {
    let pem: String = servers.iter().map(|s| std::fs::read_to_string(&s.ca_file).unwrap()).collect();
    let file = p.home().join("ca-bundle.pem");
    std::fs::write(&file, pem).unwrap();
    p.env.push(("SKILLCASK_CA_FILE".into(), file.display().to_string()));
}

#[test]
fn bare_host_credentials_are_not_sent_to_another_port() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let mut p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    p.env.push(("COMPOSER_AUTH".into(), json!({ "bearer": { "127.0.0.1": "t0ken" } }).to_string()));
    p.ok(&["install"]);
    assert!(s.log().iter().all(|l| l.ends_with("auth=false")), "{:?}", s.log());
}

#[test]
fn gitlab_token_string_and_object_forms() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let mut p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    p.env.push(("COMPOSER_AUTH".into(), json!({ "gitlab-token": { host(&s): "pt0ken" } }).to_string()));
    p.ok(&["install"]);
    let reqs = s.requests();
    assert!(
        reqs.iter()
            .all(|r| r.headers.get("private-token").map(String::as_str) == Some("pt0ken") && !r.headers.contains_key("authorization")),
        "{reqs:?}"
    );

    s.require_auth(Some("Basic dTp0MGtlbg=="));
    let mut c = clone_of(&p, &s);
    c.env.push(("COMPOSER_AUTH".into(), json!({ "gitlab-token": { host(&s): { "username": "u", "token": "t0ken" } } }).to_string()));
    c.ok(&["install"]);
}

#[test]
fn github_token_goes_to_the_api_host_only() {
    let gh = Server::start();
    let repo = Server::start();
    repo.simple("acme/one", "1.0.0", "one");
    let sha = "1".repeat(40);
    gh.put("/repos/acme/t/tags", json!([{ "name": "v1.0.0", "commit": { "sha": sha } }]).to_string());
    gh.put(&format!("/repos/acme/t/commits/{sha}"), gh_commit(&sha, 240).to_string());
    gh.put(&format!("/repos/acme/t/zipball/{sha}"), zipball(&[("SKILL.md", &skill_md("t"))]));
    gh.require_auth(Some("Bearer ght0ken"));
    let mut p = with_github(Project::new(&repo), &gh);
    trust(&mut p, &[&gh, &repo]);
    p.env.push(("GITHUB_TOKEN".into(), "ght0ken".into()));
    p.manifest(&repo, "");
    p.ok(&["add", "acme/one"]);
    p.ok(&["add", "github:acme/t"]);
    assert!(!repo.log().is_empty() && repo.log().iter().all(|l| l.ends_with("auth=false")), "{:?}", repo.log());
}

#[test]
fn github_rate_limit_is_named() {
    let s = Server::start();
    s.respond("/repos/acme/x/tags", 403, &[("x-ratelimit-remaining", "0")], "");
    let p = with_github(Project::new(&s), &s);
    p.manifest(&s, "");
    let out = p.expect(&["add", "github:acme/x"], 2);
    assert!(out.contains("GitHub API rate limit reached; set GITHUB_TOKEN"), "{out}");
}
