use std::process::Command;

fn main() {
    let commit = std::env::var("SKILLCASK_COMMIT")
        .ok()
        .or_else(|| {
            let out = Command::new("git").args(["rev-parse", "--short=12", "HEAD"]).output().ok()?;
            out.status.success().then(|| String::from_utf8_lossy(&out.stdout).trim().to_string())
        })
        .unwrap_or_else(|| "unknown".into());
    println!("cargo:rustc-env=SKILLCASK_COMMIT={commit}");
    println!("cargo:rerun-if-env-changed=SKILLCASK_COMMIT");
    println!("cargo:rerun-if-changed=.git/HEAD");
    println!("cargo:rerun-if-changed=.git/refs");
}
