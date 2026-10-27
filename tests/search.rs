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

/// A project whose only registry has `acme/beta`, with skills.sh served by `s`.
fn beta_project(s: &Server) -> Project {
    s.put(
        "/gl/packages.json",
        json!({ "packages": [], "metadata-url": "/gl/p2/%package%.json", "available-packages": ["acme/beta"] }).to_string(),
    );
    s.put(
        "/gl/p2/acme/beta.json",
        json!({ "packages": { "acme/beta": [{ "name": "acme/beta", "version": "1.0.0", "type": "ai-agent-skill",
            "description": "beta desc", "dist": { "type": "zip", "url": "/x.zip" } }] } })
        .to_string(),
    );
    s.put(
        "/api/search",
        json!({ "query": "beta", "skills": [
            { "id": "owner/repo/beta", "source": "owner/repo", "skillId": "beta", "name": "beta", "installs": 42 },
            { "id": "x", "source": "not a repo", "skillId": "beta" },
        ] })
        .to_string(),
    );
    let mut p = Project::new(s);
    p.env.push(("SKILLCASK_SKILLS_SH".into(), s.base.clone()));
    p.write(
        "skills.toml",
        &format!("[repositories]\ngl = {{ type = \"composer\", url = \"{}\" }}\n[policy]\npackagist = false\n", s.url("/gl")),
    );
    p
}

fn asked(s: &Server) -> bool {
    s.log().iter().any(|l| l.starts_with("/api/search"))
}

fn json_of(p: &Project, args: &[&str]) -> serde_json::Value {
    let o = p.run(args);
    assert_eq!(o.status.code(), Some(0), "{}", String::from_utf8_lossy(&o.stderr));
    serde_json::from_slice(&o.stdout).unwrap()
}

#[test]
fn skills_sh_is_off_until_asked_for() {
    let s = Server::start();
    let p = beta_project(&s);
    let out = p.ok(&["search", "beta"]);
    assert!(out.contains("acme/beta  beta desc") && !out.contains("skills.sh"), "{out}");
    assert_eq!(
        json_of(&p, &["search", "beta", "--json"]),
        json!({ "results": [{ "name": "acme/beta", "description": "beta desc", "source": "gl", "installs": null }], "skills-sh": null })
    );
    assert!(!asked(&s));

    let out = p.ok(&["search", "beta", "--skills-sh"]);
    assert!(out.contains("acme/beta               beta desc"), "{out}");
    assert!(out.contains("github:owner/repo/beta  42 installs, from skills.sh"), "{out}");
    assert!(s.log().iter().any(|l| l.starts_with("/api/search?q=beta&limit=20")), "{:?}", s.log());
    assert!(!p.home().join(".config/skillcask/config.toml").exists());
    let d = json_of(&p, &["search", "beta", "--json", "--skills-sh"]);
    assert_eq!(d["results"][1], json!({ "name": "github:owner/repo/beta", "description": null, "source": "skills.sh", "installs": 42 }));
    assert_eq!((d["results"].as_array().unwrap().len(), &d["skills-sh"]), (2, &json!(null)));
    p.expect(&["search", "beta", "--skills-sh", "--no-skills-sh"], 1);
    p.expect(&["search", "beta", "--remember"], 1);
}

#[test]
fn remember_writes_config_toml_and_keeps_the_rest() {
    let s = Server::start();
    let p = beta_project(&s);
    let dir = p.home().join(".config/skillcask");
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("config.toml"), "# mine\n[agents]\ntargets = [\"claude\"]\n").unwrap();
    let out = p.ok(&["search", "beta", "--skills-sh", "--remember"]);
    assert!(out.contains("github:owner/repo/beta") && out.contains("saved [search] skills-sh = true"), "{out}");
    let cfg = std::fs::read_to_string(dir.join("config.toml")).unwrap();
    assert_eq!(cfg, "# mine\n[agents]\ntargets = [\"claude\"]\n\n[search]\nskills-sh = true\n");
    assert_eq!(json_of(&p, &["search", "beta", "--json"])["results"][1]["source"], "skills.sh");
    assert_eq!(json_of(&p, &["search", "beta", "--json", "--no-skills-sh"])["skills-sh"], true);

    p.ok(&["search", "beta", "--no-skills-sh", "--remember"]);
    assert!(std::fs::read_to_string(dir.join("config.toml")).unwrap().contains("skills-sh = false"));
    assert_eq!(
        json_of(&p, &["search", "beta", "--json"]),
        json!({ "results": [{ "name": "acme/beta", "description": "beta desc", "source": "gl", "installs": null }], "skills-sh": false })
    );

    // No config dir yet: created.
    std::fs::remove_dir_all(&dir).unwrap();
    p.ok(&["search", "beta", "--no-skills-sh", "--remember"]);
    assert!(std::fs::read_to_string(dir.join("config.toml")).unwrap().contains("[search]\nskills-sh = false"));
}

#[test]
fn skills_sh_is_skipped_without_github_and_its_failure_only_warns() {
    let s = Server::start();
    let p = beta_project(&s);
    p.write(
        "skills.toml",
        &format!(
            "[repositories]\ngl = {{ type = \"composer\", url = \"{}\" }}\n[policy]\npackagist = false\nallow-sources = [\"gl\"]\n",
            s.url("/gl")
        ),
    );
    let out = p.ok(&["search", "beta", "--skills-sh"]);
    assert!(out.contains("acme/beta") && out.contains("skills.sh not searched"), "{out}");
    assert!(!asked(&s));

    p.write(
        "skills.toml",
        &format!("[repositories]\ngl = {{ type = \"composer\", url = \"{}\" }}\n[policy]\npackagist = false\n", s.url("/gl")),
    );
    s.put("/api/search", "<html>not json");
    let out = p.ok(&["search", "beta", "--skills-sh"]);
    assert!(out.contains("acme/beta  beta desc") && out.contains("warning: skills.sh:"), "{out}");
    let o = p.run(&["search", "beta", "--skills-sh", "--json"]);
    assert_eq!(serde_json::from_slice::<serde_json::Value>(&o.stdout).unwrap()["results"].as_array().unwrap().len(), 1);
}
