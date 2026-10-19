mod common;

use common::*;
use serde_json::json;

fn store_hash(p: &Project, name: &str) -> Vec<(String, Vec<u8>)> {
    let mut out = Vec::new();
    let root = p.path().join(".agents/skills").join(name);
    let mut stack = vec![root.clone()];
    while let Some(d) = stack.pop() {
        for e in std::fs::read_dir(d).unwrap() {
            let e = e.unwrap();
            if e.file_type().unwrap().is_dir() {
                stack.push(e.path());
            } else {
                out.push((e.path().strip_prefix(&root).unwrap().display().to_string(), std::fs::read(e.path()).unwrap()));
            }
        }
    }
    out.sort();
    out
}

#[test]
fn add_creates_everything_and_frozen_clone_reproduces_it() {
    let s = Server::start();
    s.simple("acme/one", "v1.2.3", "one");
    let p = Project::new(&s);
    p.write(
        "skills.toml",
        &format!("[repositories]\nfix = {{ type = \"composer\", url = \"{}\" }}\n[policy]\npackagist = false\n", s.url("/packages.json")),
    );
    p.ok(&["add", "acme/one"]);

    assert!(p.read("skills.toml").contains("\"acme/one\" = \"^1.2\""));
    let lock = p.read("skills.lock");
    assert!(lock.contains("version = \"v1.2.3\"") && lock.contains("tree-sha256") && lock.contains("reference = \"ref0\""), "{lock}");
    assert_eq!(p.read(".agents/skills/one/SKILL.md"), skill_md("one"));
    for t in [".claude/skills/one", ".junie/skills/one"] {
        let meta = std::fs::symlink_metadata(p.path().join(t)).unwrap();
        if cfg!(unix) {
            assert!(meta.file_type().is_symlink(), "{t}");
            assert_eq!(std::fs::read_link(p.path().join(t)).unwrap(), std::path::Path::new("../../.agents/skills/one"));
        }
        assert_eq!(p.read(&format!("{t}/SKILL.md")), skill_md("one"));
    }
    let gi = p.read(".gitignore");
    assert!(gi.contains("/.agents/skills/one/") && gi.contains("/.claude/skills/one") && gi.contains("/.junie/skills/one"), "{gi}");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = std::fs::metadata(p.path().join(".agents/skills/one/scripts/run.sh")).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o755);
    }
    p.ok(&["status"]);

    let c = clone_of(&p, &s);
    let mut env = c;
    env.env.push(("CI".into(), "true".into()));
    env.ok(&["install"]);
    assert_eq!(store_hash(&env, "one"), store_hash(&p, "one"));
    env.ok(&["status"]);
    assert_eq!(env.read("skills.lock"), p.read("skills.lock"));

    let again = p.ok(&["install"]);
    assert!(!again.contains("installed"), "already-installed skills are skipped: {again}");
}

#[test]
fn modified_skill_fails_status_and_tampered_zip_fails_install() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    p.ok(&["install"]);
    p.ok(&["status"]);

    p.write(".agents/skills/one/SKILL.md", &(skill_md("one") + "x"));
    let out = p.expect(&["status"], 1);
    assert!(out.contains("modified"), "{out}");
    p.expect(&["doctor"], 1);
    p.ok(&["install"]);
    p.ok(&["status"]);

    s.put("/dist/acme/one/1.0.0.zip", zipball(&[("SKILL.md", &skill_md("evil"))]));
    let c = clone_of(&p, &s);
    let out = c.expect(&["install", "--frozen"], 4);
    assert!(out.contains("sha256"), "{out}");
    assert!(!c.exists(".agents/skills/one"));
}

#[test]
fn ci_refuses_unlocked_entries_without_writing() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    s.simple("acme/two", "1.0.0", "two");
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    p.ok(&["install"]);
    let lock = p.read("skills.lock");
    let gi = p.read(".gitignore");
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n\"acme/two\" = \"^1.0\"\n");

    let mut ci = clone_of(&p, &s);
    ci.env.push(("CI".into(), "true".into()));
    let out = ci.expect(&["install"], 1);
    assert!(out.contains("acme/two: not in skills.lock"), "{out}");
    assert!(!ci.exists(".agents"));

    let out = p.expect(&["install", "--frozen"], 1);
    assert!(out.contains("out of date"), "{out}");
    assert_eq!(p.read("skills.lock"), lock);
    assert_eq!(p.read(".gitignore"), gi);
    assert!(!p.exists(".agents/skills/two"));

    p.manifest(&s, "\"acme/one\" = \"~1.0.0\"\n");
    assert!(p.expect(&["install", "--frozen"], 1).contains("constraint changed"));
}

#[test]
fn cooldown_skips_fresh_versions_and_names_eligible_date() {
    let s = Server::start();
    let z = || zipball(&[("SKILL.md", &skill_md("cool"))]);
    s.package(
        "acme/cool",
        vec![
            Ver { version: "1.1.0", time: Some(ago(1)), zip: z(), extra: None },
            Ver { version: "1.0.0", time: Some(ago(240)), zip: z(), extra: None },
        ],
    );
    s.package("acme/fresh", vec![Ver { version: "2.0.0", time: Some(ago(1)), zip: z(), extra: None }]);
    let p = Project::new(&s);
    p.manifest(&s, "");
    p.ok(&["add", "acme/cool"]);
    assert!(p.read("skills.lock").contains("version = \"1.0.0\""));
    let out = p.ok(&["outdated"]);
    assert!(out.contains("1.1.0 eligible"), "{out}");

    let before = p.read("skills.toml");
    let out = p.expect(&["add", "acme/fresh"], 1);
    assert!(out.contains("becomes eligible at") && out.contains("2.0.0"), "{out}");
    assert_eq!(p.read("skills.toml"), before);

    p.write("skills.toml", &before.replace("packagist = false", "packagist = false\nmin-release-age = \"0\""));
    p.ok(&["update"]);
    assert!(p.read("skills.lock").contains("version = \"1.1.0\""));
}

#[test]
fn version_without_time_is_kept_with_warning() {
    let s = Server::start();
    s.package("acme/notime", vec![Ver { version: "1.0.0", time: None, zip: zipball(&[("SKILL.md", &skill_md("notime"))]), extra: None }]);
    let p = Project::new(&s);
    p.manifest(&s, "");
    let out = p.ok(&["add", "acme/notime@1.0.0"]);
    assert!(out.contains("no release time"), "{out}");
    assert!(p.read("skills.toml").contains("\"acme/notime\" = \"1.0.0\""));
}

#[test]
fn typo_leaves_files_untouched() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let p = Project::new(&s);
    p.manifest(&s, "");
    let before = p.read("skills.toml");
    assert!(p.expect(&["add", "acme/onee"], 1).contains("not found"));
    assert!(p.expect(&["add", "acme/one@^9.0"], 1).contains("no version"));
    assert_eq!(p.read("skills.toml"), before);
    assert!(!p.exists("skills.lock"));
}

#[test]
fn http_basic_and_bearer_auth() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    s.require_auth(Some("Basic Z2l0bGFiLWNpLXRva2VuOmpvYnRva2Vu"));
    let mut p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    let out = p.expect(&["install", "--verbose"], 2);
    assert!(out.contains("401"), "{out}");

    let host = s.base.trim_start_matches("https://").to_string();
    p.env.push((
        "COMPOSER_AUTH".into(),
        json!({ "http-basic": { host.clone(): { "username": "gitlab-ci-token", "password": "jobtoken" } } }).to_string(),
    ));
    let seen = s.log().len();
    let out = p.ok(&["install", "--verbose"]);
    assert!(!out.contains("jobtoken") && out.contains("GET "), "token printed or no request log: {out}");
    assert!(s.log()[seen..].iter().all(|l| l.ends_with("auth=true")));

    s.require_auth(Some("Bearer t0ken"));
    let c = clone_of(&p, &s);
    c.write("auth.json", &json!({ "bearer": { host: "t0ken" } }).to_string());
    c.ok(&["install"]);
}

fn evil(entries: &[(&str, Option<u32>)]) -> Vec<u8> {
    use std::io::Write;
    let mut w = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    for (name, mode) in entries {
        let mut o = zip::write::SimpleFileOptions::default().system(zip::System::Unix);
        if let Some(m) = mode {
            o = o.unix_permissions(*m);
        }
        if mode.is_some_and(|m| m & 0o170000 == 0o120000) {
            w.add_symlink(*name, "/etc/passwd", o).unwrap();
        } else {
            w.start_file(*name, o).unwrap();
            w.write_all(b"---\nname: evil\n---\n").unwrap();
        }
    }
    w.finish().unwrap().into_inner()
}

#[test]
fn archive_attacks_are_rejected() {
    let s = Server::start();
    let cases = [
        ("acme/slip", evil(&[("SKILL.md", None), ("../../escape.txt", None)])),
        ("acme/link", evil(&[("SKILL.md", None), ("l", Some(0o120777))])),
        ("acme/abs", evil(&[("SKILL.md", None), ("/tmp/abs.txt", None)])),
    ];
    for (name, zip) in cases {
        s.package(name, vec![Ver { version: "1.0.0", time: Some(ago(240)), zip, extra: None }]);
    }
    s.simple("acme/big", "1.0.0", "big");
    let p = Project::new(&s);
    p.manifest(&s, "");
    for name in ["acme/slip", "acme/link", "acme/abs"] {
        let out = p.expect(&["add", name], 5);
        assert!(out.contains("archive"), "{name}: {out}");
    }
    assert!(!p.path().parent().unwrap().join("escape.txt").exists());
    assert!(p.expect(&["add", "acme/big", "--max-unpacked", "10"], 5).contains("archive"));
    assert!(p.expect(&["add", "acme/big", "--max-files", "1"], 5).contains("archive"));
    assert!(p.expect(&["add", "acme/big", "--max-download", "10"], 5).contains("limit"));
    assert!(!p.exists("skills.lock"));
    p.ok(&["add", "acme/big"]);
}

#[test]
fn collisions_are_errors() {
    let s = Server::start();
    s.simple("acme/a", "1.0.0", "same");
    s.simple("other/b", "1.0.0", "same");
    s.simple("acme/c", "1.0.0", "mine");
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/a\" = \"^1.0\"\n\"other/b\" = \"^1.0\"\n");
    let out = p.expect(&["install"], 1);
    assert!(out.contains("acme/a") && out.contains("other/b"), "{out}");

    p.manifest(&s, "");
    p.write(".agents/skills/mine/SKILL.md", &skill_md("mine-by-hand"));
    let out = p.expect(&["add", "acme/c"], 1);
    assert!(out.contains("not managed by skillcask"), "{out}");
    assert_eq!(p.read(".agents/skills/mine/SKILL.md"), skill_md("mine-by-hand"));
}

#[test]
fn hand_written_skills_are_linked_but_not_ignored() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    p.write(".agents/skills/local/SKILL.md", &skill_md("local"));
    p.ok(&["install"]);
    assert_eq!(p.read(".claude/skills/local/SKILL.md"), skill_md("local"));
    assert!(!p.read(".gitignore").contains("local"));
    let out = p.ok(&["status"]);
    assert!(out.contains("hand-written"), "{out}");
}

#[test]
fn remove_cleans_store_links_and_block() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    s.simple("acme/two", "1.0.0", "two");
    let p = Project::new(&s);
    p.write(".gitignore", "/vendor\n");
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n\"acme/two\" = \"^1.0\"\n");
    p.ok(&["install"]);
    p.ok(&["remove", "acme/one"]);
    assert!(!p.exists(".agents/skills/one") && !p.exists(".claude/skills/one") && !p.exists(".junie/skills/one"));
    assert!(p.exists(".agents/skills/two"));
    assert!(!p.read("skills.toml").contains("acme/one") && !p.read("skills.lock").contains("acme/one"));
    let gi = p.read(".gitignore");
    assert!(gi.starts_with("/vendor\n") && !gi.contains("/one") && gi.contains("/two"), "{gi}");
    p.ok(&["remove", "acme/two"]);
    assert_eq!(p.read(".gitignore"), "/vendor\n");
    p.expect(&["remove", "acme/nope"], 1);
}

#[test]
fn multi_skill_package_with_selection() {
    let s = Server::start();
    let zip = zipball(&[
        ("composer.json", "{}"),
        ("skills/alpha/SKILL.md", &skill_md("alpha")),
        ("skills/beta/SKILL.md", &skill_md("beta")),
        ("skills/beta/ref/x.md", "x"),
    ]);
    s.package(
        "acme/multi",
        vec![Ver { version: "1.0.0", time: Some(ago(240)), zip, extra: Some(json!(["skills/alpha/SKILL.md", "skills/beta/SKILL.md"])) }],
    );
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/multi\" = { version = \"^1.0\", skills = [\"beta\"] }\n");
    p.ok(&["install"]);
    assert!(p.exists(".agents/skills/beta/ref/x.md") && !p.exists(".agents/skills/alpha"));
    assert!(!p.exists(".agents/skills/beta/composer.json"));
    p.manifest(&s, "\"acme/multi\" = { version = \"^1.0\", skills = [\"alpha\", \"beta\"] }\n");
    p.ok(&["install"]);
    assert!(p.exists(".agents/skills/alpha/SKILL.md"));
    p.manifest(&s, "\"acme/multi\" = { version = \"^1.0\", skills = [\"gamma\"] }\n");
    assert!(p.expect(&["install"], 1).contains("gamma"));
}

#[test]
fn doctor_repairs_links_index_and_block() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    p.ok(&["install"]);
    p.ok(&["doctor"]);

    std::fs::remove_file(p.path().join(".claude/skills/one"))
        .or_else(|_| std::fs::remove_dir_all(p.path().join(".claude/skills/one")))
        .unwrap();
    p.write(".gitignore", "");
    git(p.path(), &["add", "-f", ".junie/skills/one"]);
    let out = p.expect(&["doctor"], 1);
    assert!(out.contains(".claude/skills/one") && out.contains("committed") && out.contains(".gitignore"), "{out}");
    p.ok(&["doctor", "--fix"]);
    p.ok(&["doctor"]);
    assert!(p.exists(".claude/skills/one/SKILL.md"));
    assert!(git(p.path(), &["ls-files"]).is_empty());
    assert!(p.exists(".junie/skills/one"), "git rm --cached keeps the working tree");
}

#[test]
fn copy_mode_when_symlinks_are_unavailable() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let mut p = Project::new(&s);
    p.env.push(("SKILLCASK_LINK_MODE".into(), "copy".into()));
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    p.write(".agents/skills/local/SKILL.md", &skill_md("local"));
    p.write(".skills/proj/SKILL.md", &skill_md("proj"));
    p.ok(&["install"]);
    assert_eq!(p.read(".claude/skills/proj/SKILL.md"), skill_md("proj"));
    assert!(p.read(".gitignore").contains("/.agents/skills/proj"), "store copy of a project skill is ignored");
    let meta = std::fs::symlink_metadata(p.path().join(".claude/skills/one")).unwrap();
    assert!(meta.is_dir() && !meta.file_type().is_symlink());
    assert_eq!(p.read(".claude/skills/one/SKILL.md"), skill_md("one"));
    assert!(p.read(".gitignore").contains("/.claude/skills/local"), "copies of hand-written skills are ignored");
    p.ok(&["doctor"]);
    p.ok(&["status"]);
    p.ok(&["remove", "acme/one"]);
    assert!(!p.exists(".claude/skills/one"));
    std::fs::remove_dir_all(p.path().join(".skills/proj")).unwrap();
    p.ok(&["install"]);
    assert!(!p.exists(".agents/skills/proj") && !p.exists(".claude/skills/proj"));
}

#[test]
fn publish_then_install_round_trip() {
    let s = Server::start();
    let mono = tempfile::tempdir().unwrap();
    for (n, v) in [("alpha", "1.0.0"), ("beta", "2.1.0"), ("gamma", "0.3.0")] {
        let d = mono.path().join("skills").join(n);
        std::fs::create_dir_all(d.join("scripts")).unwrap();
        std::fs::write(d.join("SKILL.md"), format!("---\nname: {n}\nversion: {v}\ndescription: {n} skill\n---\nbody\n")).unwrap();
        std::fs::write(d.join("scripts/x.sh"), "echo\n").unwrap();
    }
    std::fs::write(mono.path().join("skills/README.md"), "no frontmatter").unwrap();
    let out = mono.path().join("public");
    let publish = |p: &Project| {
        p.ok(&[
            "publish",
            "--vendor",
            "acme",
            "--base-url",
            &s.base,
            "--out",
            out.to_str().unwrap(),
            mono.path().join("skills").to_str().unwrap(),
        ])
    };
    let p = Project::new(&s);
    let text = publish(&p);
    assert!(text.contains("published acme/beta 2.1.0"), "{text}");
    s.serve_dir(&out);

    let snapshot = || {
        let mut v = Vec::new();
        for f in ["packages.json", "p2/acme/alpha.json", "p2/acme/beta.json", "dist/acme/gamma/0.3.0.zip"] {
            let m = std::fs::metadata(out.join(f)).unwrap();
            v.push((f, m.modified().unwrap(), std::fs::read(out.join(f)).unwrap()));
        }
        v
    };
    let first = snapshot();
    std::thread::sleep(std::time::Duration::from_millis(1100));
    assert!(publish(&p).contains("unchanged acme/alpha 1.0.0"));
    assert_eq!(snapshot(), first, "second publish of unchanged skills changes no file");

    p.write(
        "skills.toml",
        &format!(
            "[repositories]\nmono = {{ type = \"composer\", url = \"{}\" }}\n[skills]\n\"acme/alpha\" = \"^1.0\"\n\"acme/beta\" = \"^2.0\"\n\"acme/gamma\" = \"^0.3\"\n[policy]\npackagist = false\nmin-release-age = \"0\"\n",
            s.url("/packages.json")
        ),
    );
    p.ok(&["install"]);
    for n in ["alpha", "beta", "gamma"] {
        assert!(p.exists(&format!(".agents/skills/{n}/scripts/x.sh")));
    }
    p.ok(&["status"]);
    let found = p.ok(&["search", "bet"]);
    assert!(found.contains("acme/beta") && !found.contains("acme/alpha"), "{found}");

    std::fs::write(mono.path().join("skills/alpha/SKILL.md"), "---\nname: alpha\nversion: 1.0.0\n---\nchanged\n").unwrap();
    let o =
        p.expect(&["publish", "--vendor", "acme", "--base-url", &s.base, "--out", out.to_str().unwrap(), mono.path().to_str().unwrap()], 1);
    assert!(o.contains("different content"), "{o}");
}

#[cfg(unix)]
#[test]
fn unknown_commands_run_plugins_from_path() {
    use std::os::unix::fs::PermissionsExt;
    let s = Server::start();
    let mut p = Project::new(&s);
    let bin = tempfile::tempdir().unwrap();
    let plugin = bin.path().join("skillcask-hello");
    std::fs::write(&plugin, "#!/bin/sh\necho \"hello $*\"\nexit 7\n").unwrap();
    std::fs::set_permissions(&plugin, std::fs::Permissions::from_mode(0o755)).unwrap();
    let path = format!("{}:{}", bin.path().display(), std::env::var("PATH").unwrap());
    p.env.push(("PATH".into(), path));
    assert!(p.expect(&["hello", "a", "--b"], 7).contains("hello a --b"));
    assert!(p.expect(&["nope"], 1).contains("no skillcask-nope on PATH"));
}

#[test]
fn version_prints_commit() {
    let s = Server::start();
    let p = Project::new(&s);
    let out = p.ok(&["--version"]);
    assert!(out.starts_with("skillcask 0.") && out.contains('('), "{out}");
    p.ok(&["init"]);
    p.expect(&["init"], 1);
    p.ok(&["install"]);
}

/// End to end against Packagist: `cargo test -- --ignored`.
#[test]
#[ignore]
fn packagist_netresearch_jira() {
    let dir = tempfile::tempdir().unwrap();
    let bin = env!("CARGO_BIN_EXE_skillcask");
    let run = |args: &[&str], d: &std::path::Path| {
        let o = std::process::Command::new(bin).args(args).current_dir(d).env_remove("CI").output().unwrap();
        assert!(o.status.success(), "{args:?}: {}{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr));
    };
    git(dir.path(), &["init", "-q"]);
    run(&["add", "netresearch/agent-jira-skill"], dir.path());
    assert!(dir.path().join(".claude/skills").read_dir().unwrap().count() > 0);
    let clone = tempfile::tempdir().unwrap();
    for f in ["skills.toml", "skills.lock"] {
        std::fs::copy(dir.path().join(f), clone.path().join(f)).unwrap();
    }
    run(&["install", "--frozen"], clone.path());
    run(&["status"], clone.path());
}

#[test]
fn project_skills_in_dot_skills_are_linked_and_committable() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    let p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    p.write(".skills/mine/SKILL.md", &skill_md("mine"));
    p.ok(&["install"]);
    if cfg!(unix) {
        assert_eq!(std::fs::read_link(p.path().join(".agents/skills/mine")).unwrap(), std::path::Path::new("../../.skills/mine"));
    }
    assert_eq!(p.read(".claude/skills/mine/SKILL.md"), skill_md("mine"));
    assert_eq!(p.read(".junie/skills/mine/SKILL.md"), skill_md("mine"));
    assert!(!p.read(".gitignore").contains("mine"), "project skill links are committed");
    assert!(p.ok(&["status"]).contains("project"));
    p.ok(&["doctor"]);

    std::fs::remove_dir_all(p.path().join(".skills/mine")).unwrap();
    p.ok(&["install"]);
    assert!(!p.exists(".agents/skills/mine") && !p.exists(".claude/skills/mine"));
    assert!(p.exists(".agents/skills/one/SKILL.md"));

    p.write(".skills/one/SKILL.md", &skill_md("one"));
    assert!(p.expect(&["install"], 1).contains("both a project skill"));
}
