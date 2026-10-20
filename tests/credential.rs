//! Tokens from git's credential helper (Keychain, Credential Manager, libsecret).
mod common;

use common::*;

/// A git config in the test HOME whose helper answers `get` with `answer` and appends what it
/// is asked to store to `$HOME/stored`.
fn helper(p: &Project, answer: &str) {
    let script = format!("!f() {{ case \"$1\" in get) printf '{answer}';; store) cat >> \"$HOME/stored\";; esac; }}; f");
    std::fs::write(p.home().join(".gitconfig"), format!("[credential]\n\thelper = {script:?}\n")).unwrap();
}

#[test]
fn a_token_from_git_is_sent_unless_turned_off() {
    let s = Server::start();
    s.simple("acme/one", "1.0.0", "one");
    s.require_auth(Some("Bearer t0ken"));
    let mut p = Project::new(&s);
    p.manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    helper(&p, "username=oauth2\\npassword=t0ken\\n");
    p.ok(&["install"]);

    std::fs::remove_dir_all(p.path().join(".agents/skills/one")).unwrap();
    p.env.push(("SKILLCASK_GIT_CREDENTIALS".into(), "0".into()));
    p.expect(&["install"], 2);
}

#[test]
fn auth_set_stores_a_piped_token_with_git() {
    let s = Server::start();
    let p = Project::new(&s);
    helper(&p, "");
    let o = p.run_input(&["auth", "set", "git.example.com"], "s3cret\n");
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    let stored = std::fs::read_to_string(p.home().join("stored")).unwrap();
    assert!(stored.contains("host=git.example.com\n") && stored.contains("username=PRIVATE-TOKEN\npassword=s3cret\n"), "{stored}");
    assert!(!p.run_input(&["auth", "set", "git.example.com"], "a\nb\n").status.success(), "a newline would inject fields");
}
