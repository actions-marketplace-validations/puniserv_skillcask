//! `skillcask publish`: a static Composer repository from every versioned SKILL.md in a monorepo.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use serde_json::{Map, Value, json};
use sha1::Sha1;
use sha2::{Digest, Sha256};

use crate::bail;
use crate::error::{Context, Error, MANIFEST, Result};
use crate::manifest::valid_package_name;
use crate::skill::{SKILL_MD, frontmatter, valid_name};
use crate::version::{Stability, Version};

pub struct PublishArgs {
    pub vendor: String,
    pub base_url: Option<String>,
    /// Dist URL with `{vendor}`, `{name}` and `{version}`; default `<base-url>/dist/{vendor}/{name}/{version}.zip`.
    pub dist_url: Option<String>,
    /// Write every package into `packages.json` (Composer v1) instead of `metadata-url` + `p2/`.
    pub inline: bool,
    pub out: PathBuf,
    pub paths: Vec<PathBuf>,
}

struct Found {
    version: String,
    normalized: Version,
    description: Option<String>,
    zip: Vec<u8>,
}

pub fn publish(args: &PublishArgs) -> Result<()> {
    let base = args.base_url.as_deref().map(|b| b.trim_end_matches('/'));
    if base.is_some_and(|b| !b.starts_with("https://")) {
        bail!(MANIFEST, "--base-url must be an https:// URL");
    }
    if base.is_none() && !(args.inline && args.dist_url.is_some()) {
        bail!(MANIFEST, "--base-url is required unless both --inline and --dist-url are given");
    }
    let dist_url = match (&args.dist_url, base) {
        (Some(t), _) => t.clone(),
        (None, Some(b)) => format!("{b}/dist/{{vendor}}/{{name}}/{{version}}.zip"),
        (None, None) => unreachable!("checked above"),
    };
    if !dist_url.starts_with("https://") || !dist_url.contains("{name}") || !dist_url.contains("{version}") {
        bail!(MANIFEST, "--dist-url must be an https:// URL containing {{name}} and {{version}}");
    }
    std::fs::create_dir_all(&args.out)?;
    let out = args.out.canonicalize()?;

    let roots = if args.paths.is_empty() { vec![PathBuf::from(".")] } else { args.paths.clone() };
    let mut dirs = Vec::new();
    for r in &roots {
        find(r, &out, &mut dirs)?;
    }

    let mut found: BTreeMap<String, Vec<Found>> = BTreeMap::new();
    for dir in dirs {
        let fm = frontmatter(&std::fs::read_to_string(dir.join(SKILL_MD))?);
        let (Some(name), Some(version)) = (fm.get("name"), fm.get("version")) else { continue };
        let at = dir.display();
        if !valid_name(name) {
            bail!(MANIFEST, "{at}: invalid skill name {name:?}");
        }
        let normalized = Version::parse(version)
            .filter(|v| v.stability >= Stability::Stable)
            .filter(|_| version.chars().all(|c| c.is_ascii_alphanumeric() || ".-_".contains(c)))
            .ok_or_else(|| Error::new(MANIFEST, format!("{at}: version {version:?} is not a stable release version")))?;
        let package = fm.get("package").cloned().unwrap_or_else(|| format!("{}/{name}", args.vendor));
        if !valid_package_name(&package) {
            bail!(MANIFEST, "{at}: invalid package name {package:?}");
        }
        let versions = found.entry(package.clone()).or_default();
        if versions.iter().any(|f| f.normalized == normalized) {
            bail!(MANIFEST, "{package} {version} is defined twice");
        }
        let description = fm.get("description").filter(|d| ![">", "|", ">-", "|-"].contains(&d.as_str())).cloned();
        versions.push(Found { zip: crate::archive::zip_dir(&dir).ctx(&at)?, version: version.clone(), normalized, description });
    }

    let index_path = out.join("packages.json");
    let index: Value = match std::fs::read(&index_path) {
        Ok(b) => serde_json::from_slice(&b).map_err(|e| Error::new(MANIFEST, format!("{}: {e}", index_path.display())))?,
        Err(_) => json!({}),
    };
    let mut available: BTreeSet<String> = index
        .get("available-packages")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();
    available.extend(index.get("packages").and_then(Value::as_object).into_iter().flat_map(|m| m.keys().cloned()));
    // Earlier versions come from the inline index or the p2 file, so switching modes keeps them.
    let load = |package: &str| -> Result<Vec<Value>> {
        match index.get("packages").and_then(|p| p.get(package)) {
            Some(Value::Object(m)) => return Ok(m.values().cloned().collect()),
            Some(Value::Array(a)) => return Ok(a.clone()),
            _ => {}
        }
        let p2_path = out.join("p2").join(format!("{package}.json"));
        match std::fs::read(&p2_path) {
            Ok(b) => serde_json::from_slice::<Value>(&b)
                .ok()
                .and_then(|v| v.get("packages")?.get(package)?.as_array().cloned())
                .ok_or_else(|| Error::new(MANIFEST, format!("{}: not a Composer metadata file", p2_path.display()))),
            Err(_) => Ok(Vec::new()),
        }
    };
    let mut all: BTreeMap<String, Vec<Value>> = BTreeMap::new();
    for package in &available {
        all.insert(package.clone(), load(package)?);
    }

    // Validate everything before writing, so an immutability error leaves `out` untouched.
    let mut writes: Vec<(PathBuf, Vec<u8>)> = Vec::new();
    let mut report = Vec::new();
    for (package, versions) in found {
        let mut meta = match all.remove(&package) {
            Some(m) => m,
            None => load(&package)?,
        };
        let (vendor, name) = package.split_once('/').expect("valid package names contain /");
        for f in versions {
            let shasum = hex::encode(Sha1::digest(&f.zip));
            let normalized = f.normalized.to_string();
            let existing = meta.iter().find(|m| m.get("version_normalized").and_then(Value::as_str) == Some(normalized.as_str()));
            let state = match existing {
                Some(m) if m["dist"]["shasum"].as_str() != Some(shasum.as_str()) => {
                    bail!(MANIFEST, "{package} {} is already published with different content; bump the version", f.version)
                }
                Some(_) => "unchanged",
                None => {
                    let mut m = json!({
                        "name": package,
                        "version": f.version,
                        "version_normalized": normalized,
                        "type": "ai-agent-skill",
                        "extra": { "ai-agent-skill": SKILL_MD },
                        "dist": {
                            "type": "zip",
                            "url": dist_url.replace("{vendor}", vendor).replace("{name}", name).replace("{version}", &f.version),
                            "shasum": shasum,
                            "reference": hex::encode(Sha256::digest(&f.zip)),
                        },
                        // Truncate: rounding up would date the release in the future and fail a zero cooldown.
                        "time": jiff::Timestamp::now()
                            .round(jiff::TimestampRound::new().smallest(jiff::Unit::Second).mode(jiff::RoundMode::Trunc))
                            .map_err(|e| Error::new(MANIFEST, e.to_string()))?
                            .to_string(),
                    });
                    if let Some(d) = f.description {
                        m["description"] = d.into();
                    }
                    meta.push(m);
                    "published"
                }
            };
            writes.push((out.join("dist").join(&package).join(format!("{}.zip", f.version)), f.zip));
            report.push(format!("{state} {package} {}", f.version));
        }
        let key = |m: &Value| m.get("version_normalized").and_then(Value::as_str).and_then(Version::parse);
        meta.sort_by_key(|m| std::cmp::Reverse(key(m)));
        all.insert(package.clone(), meta);
        available.insert(package);
    }

    let index = match base.filter(|_| !args.inline) {
        Some(base) => {
            for (package, meta) in all.iter().filter(|(_, m)| !m.is_empty()) {
                writes.push((out.join("p2").join(format!("{package}.json")), pretty(&json!({ "packages": { package: meta } }))));
            }
            json!({
                "packages": {},
                "metadata-url": format!("{base}/p2/%package%.json"),
                "available-packages": available,
            })
        }
        None => {
            let by_version = |meta: Vec<Value>| -> Map<String, Value> {
                meta.into_iter().filter_map(|m| Some((m.get("version")?.as_str()?.to_string(), m))).collect()
            };
            json!({ "packages": all.into_iter().map(|(p, m)| (p, Value::Object(by_version(m)))).collect::<Map<_, _>>() })
        }
    };
    writes.push((index_path, pretty(&index)));
    for (path, bytes) in &writes {
        write_if_changed(path, bytes)?;
    }
    for line in report {
        println!("{line}");
    }
    Ok(())
}

fn find(dir: &Path, out: &Path, found: &mut Vec<PathBuf>) -> Result<()> {
    if dir.canonicalize().is_ok_and(|c| c == out) {
        return Ok(());
    }
    if dir.join(SKILL_MD).is_file() {
        found.push(dir.to_path_buf());
    }
    let mut children: Vec<_> = std::fs::read_dir(dir)?.collect::<std::io::Result<_>>()?;
    children.sort_by_key(|e| e.file_name());
    for e in children {
        let name = e.file_name();
        let name = name.to_string_lossy();
        if e.file_type()?.is_dir() && !name.starts_with('.') && name != "target" && name != "node_modules" {
            find(&e.path(), out, found)?;
        }
    }
    Ok(())
}

fn pretty(v: &Value) -> Vec<u8> {
    let mut s = serde_json::to_string_pretty(v).expect("json values serialise");
    s.push('\n');
    s.into_bytes()
}

fn write_if_changed(path: &Path, bytes: &[u8]) -> Result<()> {
    if std::fs::read(path).is_ok_and(|b| b == bytes) {
        return Ok(());
    }
    if let Some(p) = path.parent() {
        std::fs::create_dir_all(p)?;
    }
    std::fs::write(path, bytes)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn skill(root: &Path, dir: &str, name: &str, version: &str, body: &str) {
        let d = root.join(dir);
        std::fs::create_dir_all(&d).unwrap();
        std::fs::write(d.join(SKILL_MD), format!("---\nname: {name}\nversion: {version}\ndescription: d\n---\n{body}")).unwrap();
    }

    fn snapshot(dir: &Path) -> BTreeMap<PathBuf, (Vec<u8>, std::time::SystemTime)> {
        let mut out = BTreeMap::new();
        let mut stack = vec![dir.to_path_buf()];
        while let Some(d) = stack.pop() {
            for e in std::fs::read_dir(d).unwrap() {
                let p = e.unwrap().path();
                if p.is_dir() {
                    stack.push(p);
                } else {
                    out.insert(p.clone(), (std::fs::read(&p).unwrap(), p.metadata().unwrap().modified().unwrap()));
                }
            }
        }
        out
    }

    #[test]
    fn publishes_immutably() {
        let src = tempfile::tempdir().unwrap();
        let out = tempfile::tempdir().unwrap();
        skill(src.path(), "skills/a", "alpha", "1.0.0", "a");
        skill(src.path(), "skills/b", "beta", "2.1.0", "b");
        skill(src.path(), "nested/deep/c", "gamma", "0.3.0", "c");
        skill(src.path(), "skills/noversion", "nov", "", "x");
        std::fs::write(src.path().join("skills/noversion/SKILL.md"), "---\nname: nov\n---\n").unwrap();
        let args = PublishArgs {
            vendor: "acme".into(),
            base_url: Some("https://example.com/repo/".into()),
            dist_url: None,
            inline: false,
            out: out.path().into(),
            paths: vec![src.path().into()],
        };
        publish(&args).unwrap();

        let index: Value = serde_json::from_slice(&std::fs::read(out.path().join("packages.json")).unwrap()).unwrap();
        assert_eq!(index["metadata-url"], "https://example.com/repo/p2/%package%.json");
        assert_eq!(index["available-packages"], json!(["acme/alpha", "acme/beta", "acme/gamma"]));
        let p2: Value = serde_json::from_slice(&std::fs::read(out.path().join("p2/acme/beta.json")).unwrap()).unwrap();
        let v = &p2["packages"]["acme/beta"][0];
        assert_eq!(v["version_normalized"], "2.1.0.0");
        assert_eq!(v["dist"]["url"], "https://example.com/repo/dist/acme/beta/2.1.0.zip");
        let zip = std::fs::read(out.path().join("dist/acme/beta/2.1.0.zip")).unwrap();
        assert_eq!(v["dist"]["shasum"], hex::encode(Sha1::digest(&zip)));

        let before = snapshot(out.path());
        std::thread::sleep(std::time::Duration::from_millis(1100));
        publish(&args).unwrap();
        assert_eq!(snapshot(out.path()), before);

        skill(src.path(), "skills/a", "alpha", "1.0.0", "changed");
        assert!(publish(&args).unwrap_err().msg.contains("acme/alpha 1.0.0"));

        skill(src.path(), "skills/a", "alpha", "1.1.0", "changed");
        publish(&args).unwrap();
        let p2: Value = serde_json::from_slice(&std::fs::read(out.path().join("p2/acme/alpha.json")).unwrap()).unwrap();
        let versions: Vec<_> =
            p2["packages"]["acme/alpha"].as_array().unwrap().iter().map(|v| v["version"].as_str().unwrap().to_string()).collect();
        assert_eq!(versions, ["1.1.0", "1.0.0"]);
        assert!(out.path().join("dist/acme/alpha/1.0.0.zip").exists());
    }

    #[test]
    fn rejects_bad_input() {
        let src = tempfile::tempdir().unwrap();
        let out = tempfile::tempdir().unwrap();
        let args = |base: &str| PublishArgs {
            vendor: "acme".into(),
            base_url: Some(base.into()),
            dist_url: None,
            inline: false,
            out: out.path().into(),
            paths: vec![src.path().into()],
        };
        assert!(publish(&args("http://insecure")).is_err());
        skill(src.path(), "a", "Bad_Name", "1.0.0", "");
        assert!(publish(&args("https://x")).is_err());
        skill(src.path(), "a", "ok", "1.0.0-beta1", "");
        assert!(publish(&args("https://x")).is_err());
        skill(src.path(), "a", "ok", "1.0.0", "");
        skill(src.path(), "b", "ok", "1.0.0", "other");
        assert!(publish(&args("https://x")).unwrap_err().msg.contains("defined twice"));
        let no_base = PublishArgs { base_url: None, ..args("https://x") };
        assert!(publish(&no_base).unwrap_err().msg.contains("--base-url is required"));
        let bad_tpl = PublishArgs { inline: true, dist_url: Some("https://x/{name}.zip".into()), ..no_base };
        assert!(publish(&bad_tpl).unwrap_err().msg.contains("{version}"));
    }

    #[test]
    fn publishes_inline_with_dist_template() {
        let src = tempfile::tempdir().unwrap();
        let out = tempfile::tempdir().unwrap();
        skill(src.path(), "a", "alpha", "1.0.0", "a");
        let mut args = PublishArgs {
            vendor: "acme".into(),
            base_url: Some("https://example.com/repo".into()),
            dist_url: None,
            inline: false,
            out: out.path().into(),
            paths: vec![src.path().into()],
        };
        publish(&args).unwrap();
        // Switching to inline keeps versions published through p2.
        args.base_url = None;
        args.inline = true;
        args.dist_url = Some("https://git.example.com/generic/{vendor}-{name}/{version}/{name}-{version}.zip".into());
        skill(src.path(), "a", "alpha", "1.1.0", "a2");
        skill(src.path(), "b", "beta", "2.0.0", "b");
        publish(&args).unwrap();
        let index: Value = serde_json::from_slice(&std::fs::read(out.path().join("packages.json")).unwrap()).unwrap();
        assert!(index.get("metadata-url").is_none());
        let alpha = &index["packages"]["acme/alpha"];
        assert_eq!(alpha["1.0.0"]["dist"]["url"], "https://example.com/repo/dist/acme/alpha/1.0.0.zip", "published URLs are immutable");
        assert_eq!(alpha["1.1.0"]["dist"]["url"], "https://git.example.com/generic/acme-alpha/1.1.0/alpha-1.1.0.zip");
        assert_eq!(index["packages"]["acme/beta"]["2.0.0"]["version_normalized"], "2.0.0.0");
        assert!(out.path().join("dist/acme/beta/2.0.0.zip").exists());

        let before = std::fs::read(out.path().join("packages.json")).unwrap();
        publish(&args).unwrap();
        assert_eq!(std::fs::read(out.path().join("packages.json")).unwrap(), before);
        skill(src.path(), "b", "beta", "2.0.0", "changed");
        assert!(publish(&args).unwrap_err().msg.contains("acme/beta 2.0.0"));
    }
}
