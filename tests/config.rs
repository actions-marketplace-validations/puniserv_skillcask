//! `skillcask config` (D48).
mod common;

use common::*;
use serde_json::json;

fn json_of(p: &Project, args: &[&str]) -> serde_json::Value {
    let o = p.run(args);
    assert_eq!(o.status.code(), Some(0), "{}", String::from_utf8_lossy(&o.stderr));
    serde_json::from_slice(&o.stdout).unwrap()
}

fn config_toml(p: &Project) -> String {
    std::fs::read_to_string(p.home().join(".config/skillcask/config.toml")).unwrap_or_default()
}

#[test]
fn sets_reads_and_unsets_project_keys_keeping_the_file() {
    let s = Server::start();
    let p = Project::new(&s);
    p.write("skills.toml", "# mine\n[policy]\nmin-release-age = \"3d\"   # cooldown\n");
    p.ok(&["config", "policy.min-release-age", "5d"]);
    p.ok(&["config", "policy.allow-sources", "packagist", "github"]);
    p.ok(&["config", "agents.targets", "claude", "kiro"]);
    assert_eq!(
        p.read("skills.toml"),
        "# mine\n[policy]\nmin-release-age = \"5d\"   # cooldown\nallow-sources = [\"packagist\", \"github\"]\n\n[agents]\ntargets = [\"claude\", \"kiro\"]\n"
    );
    assert_eq!(p.ok(&["config", "policy.min-release-age"]), "\"120h\"\n");
    assert_eq!(p.ok(&["config", "agents.targets"]), "[\"claude\", \"kiro\"]\n");

    p.ok(&["config", "--unset", "policy.allow-sources"]);
    assert!(!p.read("skills.toml").contains("allow-sources"));
    let e = p.expect(&["config", "policy.allow-sources"], 1);
    assert!(e.contains("policy.allow-sources is not set"), "{e}");
    let out = p.ok(&["config"]);
    assert!(out.contains("policy.min-release-age = \"120h\" (skills.toml)\n"), "{out}");
    assert!(out.contains("policy.packagist = true (default)\n"), "{out}");
    assert!(out.contains("policy.allow-sources not set\n"), "{out}");
    assert!(out.contains("agents.targets = [\"claude\", \"kiro\"] (skills.toml)\n"), "{out}");
}

#[test]
fn invalid_values_and_unknown_keys_leave_the_file_alone() {
    let s = Server::start();
    let p = Project::new(&s);
    p.write("skills.toml", "[policy]\nallow-ranges = true\n");
    for (args, msg) in [
        (&["config", "policy.allow-ranges", "maybe"][..], "policy.allow-ranges must be true or false"),
        (&["config", "policy.min-release-age", "soon"], "invalid duration"),
        (&["config", "policy.min-release-age", "1d", "2d"], "takes one value"),
        (&["config", "policy.allow-sources", "nope"], "unknown repository \"nope\""),
        (&["config", "agents.targets", "bogus"], "unknown agent \"bogus\""),
        (&["config", "policy.typo", "true"], "unknown key \"policy.typo\""),
    ] {
        let e = p.expect(args, 1);
        assert!(e.contains(msg), "{args:?}: {e}");
    }
    assert_eq!(p.read("skills.toml"), "[policy]\nallow-ranges = true\n");

    p.config("[search]\nskills-sh = true\n");
    let e = p.global(&["config", "search.skills-sh", "yes"], 1);
    assert!(e.contains("search.skills-sh must be true or false"), "{e}");
    let e = p.global(&["config", "policy.enforce", "packagist"], 1);
    assert!(e.contains("policy.enforce lists packagist, which policy does not set"), "{e}");
    let e = p.global(&["config", "policy.allow-sources", "acme"], 1);
    assert!(e.contains("only accepted in skills.toml"), "{e}");
    assert_eq!(config_toml(&p), "[search]\nskills-sh = true\n");
}

#[test]
fn personal_keys_need_global() {
    let s = Server::start();
    let p = Project::new(&s);
    p.write("skills.toml", "");
    for (args, hint) in [
        (&["config", "search.skills-sh", "true"][..], "hint: skillcask -g config search.skills-sh true"),
        (&["config", "--unset", "policy.enforce"], "hint: skillcask -g config --unset policy.enforce"),
    ] {
        let e = p.expect(args, 1);
        assert!(e.contains("is a personal setting, kept in config.toml, not skills.toml") && e.contains(hint), "{e}");
    }
    assert_eq!(p.read("skills.toml"), "");
    assert_eq!(config_toml(&p), "");
}

#[test]
fn global_writes_config_toml_and_creates_its_dir() {
    let s = Server::start();
    let p = Project::new(&s);
    p.global(&["config", "search.skills-sh", "true"], 0);
    p.global(&["config", "policy.allow-sources", "https://git.example.com/", "github"], 0);
    p.global(&["config", "policy.enforce", "allow-sources"], 0);
    assert_eq!(
        config_toml(&p),
        "[search]\nskills-sh = true\n\n[policy]\nallow-sources = [\"https://git.example.com/\", \"github\"]\nenforce = [\"allow-sources\"]\n"
    );
    assert_eq!(p.global(&["config", "search.skills-sh"], 0), "true\n");
    let out = p.global(&["config"], 0);
    assert!(out.contains("policy.allow-sources = [\"https://git.example.com/\", \"github\"] (config.toml, enforced)\n"), "{out}");
    assert!(out.contains("policy.enforce = [\"allow-sources\"] (config.toml)\n"), "{out}");

    // Lifting the key it enforces first is refused.
    let e = p.global(&["config", "--unset", "policy.allow-sources"], 1);
    assert!(e.contains("policy.enforce lists allow-sources"), "{e}");
    p.global(&["config", "--unset", "policy.enforce"], 0);
    p.global(&["config", "--unset", "policy.allow-sources"], 0);
    assert_eq!(config_toml(&p), "[search]\nskills-sh = true\n\n[policy]\n");
}

#[test]
fn json_names_where_each_setting_comes_from() {
    let s = Server::start();
    let mut p = Project::new(&s);
    p.write("skills.toml", "[policy]\nallow-ranges = false\n");
    p.config(
        "[policy]\nmin-release-age = \"1d\"\nallow-sources = [\"github\"]\nenforce = [\"allow-sources\"]\n[agents]\ntargets = [\"kiro\"]\n",
    );
    p.env.push(("SKILLCASK_DENY_PATTERNS".into(), "true".into()));
    let d = json_of(&p, &["config", "--json"]);
    assert!(d["file"].as_str().unwrap().ends_with("skills.toml"), "{d}");
    assert_eq!(
        d["settings"],
        json!({
            "policy.min-release-age": { "value": "24h", "from": "config.toml" },
            "policy.allow-ranges": { "value": false, "from": "skills.toml" },
            "policy.packagist": { "value": true, "from": "default" },
            "policy.github-requires": { "value": false, "from": "default" },
            "policy.allow-sources": { "value": ["github"], "from": "config.toml, enforced" },
            "policy.deny-patterns": { "value": true, "from": "environment" },
            "agents.targets": { "value": ["kiro"], "from": "config.toml" },
            "search.skills-sh": { "value": null, "from": null },
        })
    );
    assert_eq!(json_of(&p, &["config", "policy.allow-ranges", "--json"]), json!({ "value": false, "from": "skills.toml" }));

    // The project may not loosen an enforced key.
    let e = p.expect(&["config", "policy.allow-sources", "packagist"], 1);
    assert!(e.contains("policy.allow-sources is enforced"), "{e}");
    assert_eq!(p.read("skills.toml"), "[policy]\nallow-ranges = false\n");
    let out = p.ok(&["config", "policy.deny-patterns", "false"]);
    assert!(out.contains("warning: the environment overrides it here: policy.deny-patterns = true"), "{out}");
}

#[test]
fn status_shows_the_skills_sh_setting() {
    let s = Server::start();
    let p = Project::new(&s);
    p.write("skills.toml", "");
    assert!(p.ok(&["status"]).contains("search.skills-sh not set\n"));
    assert_eq!(json_of(&p, &["status", "--json"])["skills-sh"], json!(null));
    p.global(&["config", "search.skills-sh", "false"], 0);
    assert!(p.ok(&["status"]).contains("search.skills-sh = false (config.toml)\n"));
    assert_eq!(json_of(&p, &["status", "--json"])["skills-sh"], json!(false));
}

#[test]
fn search_remember_without_a_query_only_saves() {
    let s = Server::start();
    let p = Project::new(&s);
    let out = p.ok(&["search", "--skills-sh", "--remember"]);
    assert!(out.contains("saved [search] skills-sh = true"), "{out}");
    assert_eq!(config_toml(&p), "[search]\nskills-sh = true\n");
    assert!(s.log().is_empty(), "{:?}", s.log());
    p.expect(&["search"], 1);
    p.expect(&["search", "--skills-sh"], 1);
}

#[cfg(unix)]
#[test]
fn edit_checks_the_file_and_keeps_a_broken_edit() {
    use std::os::unix::fs::PermissionsExt;
    let s = Server::start();
    let mut p = Project::new(&s);
    p.write("skills.toml", "[policy]\nallow-ranges = true\n");
    let editor = p.home().join("editor.sh");
    std::fs::write(&editor, "#!/bin/sh\necho 'allow-ranges = 1' >> \"$1\"\n").unwrap();
    std::fs::set_permissions(&editor, std::fs::Permissions::from_mode(0o755)).unwrap();
    p.env.push(("VISUAL".into(), String::new()));
    p.env.push(("EDITOR".into(), editor.display().to_string()));
    let e = p.expect(&["config", "edit"], 1);
    assert!(e.contains("duplicate key") && e.contains("hint: your edit is kept in skills.toml"), "{e}");
    assert!(p.read("skills.toml").ends_with("allow-ranges = 1\n"));

    std::fs::write(&editor, "#!/bin/sh\nprintf '[search]\\nskills-sh = true\\n' >> \"$1\"\n").unwrap();
    let out = p.global(&["config", "edit"], 0);
    assert!(out.contains("checked"), "{out}");
    assert_eq!(config_toml(&p), "[search]\nskills-sh = true\n");
}
