//! skillcask never deletes or overwrites data it does not own.
mod common;

use common::*;

fn one(s: &Server) -> Project {
    s.simple("acme/one", "1.0.0", "one");
    let p = Project::new(s);
    p.manifest(s, "\"acme/one\" = \"^1.0\"\n");
    p
}

fn mtime(p: &Project, rel: &str) -> std::time::SystemTime {
    std::fs::metadata(p.path().join(rel)).unwrap().modified().unwrap()
}

#[test]
fn unreadable_gitignore_is_left_byte_identical() {
    let s = Server::start();
    let p = one(&s);
    let gi = b"/vendor\n/caf\xe9\n";
    std::fs::write(p.path().join(".gitignore"), gi).unwrap();
    let o = p.run(&["install"]);
    assert!(!o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    assert_eq!(std::fs::read(p.path().join(".gitignore")).unwrap(), gi);

    p.global_manifest(&s, "\"acme/one\" = \"^1.0\"\n");
    let list = p.home().join(".agents/skills/.skillcask-installed");
    std::fs::create_dir_all(list.parent().unwrap()).unwrap();
    std::fs::write(&list, gi).unwrap();
    assert!(!p.run(&["--global", "install"]).status.success());
    assert_eq!(std::fs::read(&list).unwrap(), gi);
}

#[test]
fn crlf_gitignore_keeps_its_line_endings() {
    let s = Server::start();
    let p = one(&s);
    p.write(".gitignore", "/vendor\r\n/secrets.env\r\n");
    p.ok(&["install"]);
    let gi = p.read(".gitignore");
    assert!(gi.starts_with("/vendor\r\n/secrets.env\r\n") && gi.contains("/.agents/skills/one/\r\n"), "{gi:?}");
    assert!(!gi.replace("\r\n", "").contains('\n'), "{gi:?}");
    let before = mtime(&p, ".gitignore");
    std::thread::sleep(std::time::Duration::from_millis(50));
    p.ok(&["install"]);
    assert_eq!(p.read(".gitignore"), gi);
    assert_eq!(mtime(&p, ".gitignore"), before, "the second run rewrote .gitignore");
}
