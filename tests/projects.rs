//! `projects`: directories with skills.toml under the given ones (D40).
use std::process::Command;

fn run(args: &[&std::ffi::OsStr]) -> (i32, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_skillcask")).args(args).env("SKILLCASK_AGENT", "0").output().unwrap();
    (out.status.code().unwrap(), String::from_utf8(out.stdout).unwrap())
}

#[test]
fn lists_projects_and_skips_hidden_dependency_and_deep_dirs() {
    let tmp = tempfile::tempdir().unwrap();
    let root = std::path::absolute(tmp.path()).unwrap();
    for dir in ["", "a", "b/c", ".hidden/p", "a/node_modules/x", "d/vendor/y", "e/target/z", "1/2/3/4/5/6", "1/2/3/4/5/6/7"] {
        std::fs::create_dir_all(root.join(dir)).unwrap();
        std::fs::write(root.join(dir).join("skills.toml"), "").unwrap();
    }
    let (code, out) = run(&["projects".as_ref(), "--json".as_ref(), root.as_os_str()]);
    assert_eq!(code, 0);
    let doc: serde_json::Value = serde_json::from_str(&out).unwrap();
    let found: Vec<_> = doc["projects"].as_array().unwrap().iter().map(|p| p["path"].as_str().unwrap().to_string()).collect();
    let want: Vec<_> = ["", "1/2/3/4/5/6", "a", "b/c"]
        .iter()
        .map(|d| d.split('/').fold(root.clone(), |p, s| p.join(s)).to_string_lossy().into_owned())
        .collect();
    assert_eq!(found, want.iter().map(|p| p.trim_end_matches(['/', '\\']).to_string()).collect::<Vec<_>>());
}

#[test]
fn a_missing_directory_is_an_io_error() {
    let tmp = tempfile::tempdir().unwrap();
    let (code, _) = run(&["projects".as_ref(), tmp.path().join("nope").as_os_str()]);
    assert_eq!(code, 5);
}
