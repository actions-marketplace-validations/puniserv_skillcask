use std::process::Command;

fn main() {
    let commit = std::env::var("SKILLCASK_COMMIT")
        .ok()
        .or_else(|| {
            let out = Command::new("git").args(["rev-parse", "--short=12", "HEAD"]).output().ok()?;
            out.status.success().then(|| String::from_utf8_lossy(&out.stdout).trim().to_string())
        })
        .or_else(vcs_info_sha)
        .unwrap_or_else(|| "unknown".into());
    println!("cargo:rustc-env=SKILLCASK_COMMIT={commit}");
    println!("cargo:rerun-if-env-changed=SKILLCASK_COMMIT");
    println!("cargo:rerun-if-changed=.git/HEAD");
    println!("cargo:rerun-if-changed=.git/refs");
}

/// Crates published by cargo carry the commit in `.cargo_vcs_info.json` instead of a `.git` dir.
fn vcs_info_sha() -> Option<String> {
    let text = std::fs::read_to_string(".cargo_vcs_info.json").ok()?;
    let sha = text.split("\"sha1\"").nth(1)?.split('"').nth(1)?;
    Some(sha.chars().take(12).collect())
}
