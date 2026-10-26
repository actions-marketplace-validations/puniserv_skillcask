//! `--json` (D32): one document on stdout, warnings and errors on stderr.
mod common;

use common::*;
use serde_json::{Value, json};

fn doc(p: &Project, args: &[&str], code: i32) -> Value {
    let o = p.run(args);
    assert_eq!(o.status.code(), Some(code), "{args:?}: {}", String::from_utf8_lossy(&o.stderr));
    let out = String::from_utf8_lossy(&o.stdout);
    assert_eq!(out.lines().count(), 1, "one line: {out}");
    serde_json::from_str(&out).unwrap_or_else(|e| panic!("{e}: {out}"))
}

#[test]
fn status_outdated_info_and_doctor() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    p.ok(&["install"]);

    let st = doc(&p, &["status", "--json"], 0);
    assert_eq!(st["ok"], true);
    assert_eq!(st["entries"][0], json!({ "package": "acme/one", "version": "1.0.0", "skill": "one", "state": "ok", "ok": true, "adopt": null }));
    assert_eq!(st["policy"]["packagist"], json!({ "value": false, "from": "skills.toml" }));
    std::fs::write(p.path().join(".agents/skills/one/SKILL.md"), "changed").unwrap();
    let st = doc(&p, &["status", "--json"], 1);
    assert_eq!((st["ok"].clone(), st["entries"][0]["state"].clone()), (json!(false), json!("modified")));
    p.ok(&["install"]);

    let zip = zipball(&[("SKILL.md", &skill_md("one")), ("scripts/run.sh", "#!/bin/sh\necho hi\n")]);
    s.package(
        "acme/one",
        vec![
            Ver { version: "1.1.0", time: Some(ago(1)), zip: zip.clone(), extra: None },
            Ver { version: "1.0.0", time: Some(ago(240)), zip, extra: None },
        ],
    );
    let out = doc(&p, &["outdated", "--json"], 0);
    let row = &out["packages"][0];
    assert_eq!((row["locked"].clone(), row["within"].clone(), row["latest"].clone()), (json!("1.0.0"), json!("1.1.0"), json!("1.1.0")));
    assert!(row["note"].as_str().unwrap().starts_with("1.1.0 eligible "), "{row}");

    let info = doc(&p, &["info", "acme/one", "--json"], 0);
    assert_eq!(info["source"], "composer");
    assert_eq!(info["locked"], true);
    assert_eq!(info["skills"][0], json!({ "name": "one", "description": "test skill one" }));
    assert_eq!(info["why"], json!(["acme/one: in skills.toml as \"^1.0\""]));
    let sk = doc(&p, &["info", "one", "--json"], 0);
    assert_eq!((sk["kind"].clone(), sk["package"].clone()), (json!("package"), json!("acme/one")));

    let d = doc(&p, &["doctor", "--json"], 0);
    assert_eq!(d["ok"], true);
    assert!(d["passed"].as_array().unwrap().iter().any(|x| x.as_str().unwrap().starts_with("installed: 1 skill")), "{d}");
    std::fs::remove_dir_all(p.path().join(".agents/skills/one")).unwrap();
    let d = doc(&p, &["doctor", "--json"], 1);
    assert!(d["problems"].as_array().unwrap().iter().any(|x| x.as_str().unwrap().contains("not installed")), "{d}");
}

#[test]
fn search_escapes_package_text() {
    let s = Server::start();
    s.put(
        "/gl/packages.json",
        json!({ "packages": [], "metadata-url": "/gl/p2/%package%.json", "available-packages": ["acme/beta"] }).to_string(),
    );
    s.put(
        "/gl/p2/acme/beta.json",
        json!({ "packages": { "acme/beta": [{ "name": "acme/beta", "version": "1.0.0", "type": "ai-agent-skill",
            "description": "beta \u{202E}txt", "dist": { "type": "zip", "url": "/x.zip" } }] } })
        .to_string(),
    );
    let p = Project::new(&s);
    p.write(
        "skills.toml",
        &format!("[repositories]\ngl = {{ type = \"composer\", url = \"{}\" }}\n[policy]\npackagist = false\n", s.url("/gl")),
    );
    let out = doc(&p, &["search", "beta", "--json"], 0);
    assert_eq!(out, json!({ "results": [{ "name": "acme/beta", "description": "beta <U+202E>txt" }] }));
}
