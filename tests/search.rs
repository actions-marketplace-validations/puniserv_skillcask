//! `search` outside Packagist.
mod common;

use common::*;
use serde_json::json;

#[test]
fn search_lists_gitlab_skill_packages_and_survives_a_broken_repository() {
    let s = Server::start();
    // GitLab's Composer registry lists names only through `provider-includes`.
    s.put(
        "/gl/packages.json",
        json!({ "packages": [], "metadata-url": "/gl/p2/%package%.json", "provider-includes": { "p/%hash%.json": { "sha256": "abc" } } })
            .to_string(),
    );
    s.put(
        "/gl/p/abc.json",
        json!({ "providers": { "acme/beta-skill": { "sha256": "1" }, "acme/beta-lib": { "sha256": "2" } } }).to_string(),
    );
    let meta = |name: &str, kind: &str| {
        json!({ "packages": { name: [{ "name": name, "version": "1.0.0", "type": kind, "description": format!("{name} desc"),
            "dist": { "type": "zip", "url": "/x.zip" } }] } })
        .to_string()
    };
    s.put("/gl/p2/acme/beta-skill.json", meta("acme/beta-skill", "ai-agent-skill"));
    s.put("/gl/p2/acme/beta-lib.json", meta("acme/beta-lib", "library"));
    let p = Project::new(&s);
    p.write(
        "skills.toml",
        &format!(
            "[repositories]\nbroken = {{ type = \"composer\", url = \"{}\" }}\ngl = {{ type = \"composer\", url = \"{}\" }}\n[policy]\npackagist = false\n",
            s.url("/nope"),
            s.url("/gl")
        ),
    );
    let out = p.ok(&["search", "beta"]);
    assert!(out.contains("acme/beta-skill  acme/beta-skill desc"), "{out}");
    assert!(!out.contains("acme/beta-lib"), "{out}");
    assert!(out.contains("warning: repository broken:"), "{out}");

    p.write(
        "skills.toml",
        &format!("[repositories]\nbroken = {{ type = \"composer\", url = \"{}\" }}\n[policy]\npackagist = false\n", s.url("/nope")),
    );
    p.expect(&["search", "beta"], 3);
}
