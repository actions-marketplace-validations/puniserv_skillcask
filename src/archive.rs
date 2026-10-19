//! Safe zip extraction for installs and deterministic zips for `publish`.

use std::collections::BTreeSet;
use std::io::{Cursor, Read, Write};
use std::path::Path;

use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, System, ZipArchive, ZipWriter};

use crate::bail;
use crate::error::{IO, Result};
use crate::skill::{FileEntry, scan_dir};

const S_IFMT: u32 = 0o170000;
const S_IFREG: u32 = 0o100000;
const S_IFDIR: u32 = 0o040000;

#[derive(Clone, Copy, Debug)]
pub struct Limits {
    pub download: u64,
    pub unpacked: u64,
    pub files: usize,
}

impl Default for Limits {
    fn default() -> Self {
        Limits { download: 50 << 20, unpacked: 100 << 20, files: 5000 }
    }
}

struct Entry {
    index: usize,
    parts: Vec<String>,
    dir: bool,
    link: bool,
    exec: bool,
}

pub struct Extracted {
    pub files: Vec<FileEntry>,
    pub links: Vec<Link>,
}

/// A symlink in the archive. Never written as a link: when it points to a regular file in the
/// archive it is written as a copy of that file (`CLAUDE.md -> AGENTS.md` is common in skills).
pub struct Link {
    pub path: String,
    /// Normalised target, set only when it is a regular file in the archive.
    pub target: Option<String>,
}

/// Extracts into `dest` (an existing empty directory); paths are relative to the stripped root.
pub fn extract(zip: &[u8], dest: &Path, limits: &Limits) -> Result<Extracted> {
    let mut archive = ZipArchive::new(Cursor::new(zip))?;
    let mut entries = Vec::new();
    let (mut files, mut declared) = (0usize, 0u64);
    for index in 0..archive.len() {
        let f = archive.by_index(index)?;
        let raw = f.name()?.to_string();
        if raw.starts_with('/') || raw.contains(['\\', ':', '\0']) {
            bail!(IO, "archive: unsafe entry name {raw:?}");
        }
        let parts: Vec<String> = raw.split('/').filter(|p| !p.is_empty() && *p != ".").map(String::from).collect();
        if parts.iter().any(|p| p == "..") {
            bail!(IO, "archive: unsafe entry name {raw:?}");
        }
        let mode = f.unix_mode().unwrap_or(0);
        let kind = mode & S_IFMT;
        let dir = f.is_dir();
        let link = f.is_symlink() && !dir;
        if !(link || kind == 0 || kind == S_IFREG || dir && kind == S_IFDIR) {
            bail!(IO, "archive: {raw:?} is not a regular file or directory");
        }
        if parts.is_empty() {
            continue;
        }
        if !dir {
            files += 1;
            declared = declared.saturating_add(f.size());
            if files > limits.files {
                bail!(IO, "archive: more than {} files", limits.files);
            }
            if declared > limits.unpacked {
                bail!(IO, "archive: unpacked size exceeds {} bytes", limits.unpacked);
            }
        }
        entries.push(Entry { index, parts, dir, link, exec: mode & 0o111 != 0 });
    }

    let top = entries.first().map(|e| e.parts[0].clone());
    let strip = top.is_some_and(|t| entries.iter().all(|e| e.parts[0] == t && (e.parts.len() > 1 || e.dir)));
    if strip {
        for e in &mut entries {
            e.parts.remove(0);
        }
        entries.retain(|e| !e.parts.is_empty());
    }

    let mut ancestors = BTreeSet::new();
    for e in entries.iter().filter(|e| !e.dir) {
        for i in 1..e.parts.len() {
            ancestors.insert(e.parts[..i].join("/"));
        }
    }
    if let Some(e) = entries.iter().find(|e| e.dir && !ancestors.contains(&e.parts.join("/"))) {
        bail!(IO, "archive: empty directory {:?}", e.parts.join("/"));
    }

    let mut out = Vec::new();
    let mut written = 0u64;
    for e in entries.iter().filter(|e| !e.dir && !e.link) {
        let rel = e.parts.join("/");
        let mut content = Vec::new();
        let budget = limits.unpacked - written;
        archive.by_index(e.index)?.take(budget + 1).read_to_end(&mut content)?;
        written += content.len() as u64;
        if written > limits.unpacked {
            bail!(IO, "archive: unpacked size exceeds {} bytes", limits.unpacked);
        }
        let path = dest.join(&rel);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut file = std::fs::File::create_new(&path).map_err(|err| crate::error::Error::new(IO, format!("archive: {rel}: {err}")))?;
        file.write_all(&content)?;
        set_mode(&path, e.exec)?;
        out.push(FileEntry::new(rel, e.exec, &content));
    }

    let mut links = Vec::new();
    for e in entries.iter().filter(|e| e.link) {
        let rel = e.parts.join("/");
        let mut raw = String::new();
        archive.by_index(e.index)?.take(4096).read_to_string(&mut raw)?;
        let target = resolve(&e.parts[..e.parts.len() - 1], &raw).filter(|t| out.iter().any(|f| &f.path == t));
        if let Some(t) = &target {
            let src = out.iter().find(|f| &f.path == t).cloned().expect("checked above");
            let content = std::fs::read(dest.join(t))?;
            written += content.len() as u64;
            if written > limits.unpacked {
                bail!(IO, "archive: unpacked size exceeds {} bytes", limits.unpacked);
            }
            let path = dest.join(&rel);
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::File::create_new(&path)
                .and_then(|mut f| f.write_all(&content))
                .map_err(|err| crate::error::Error::new(IO, format!("archive: {rel}: {err}")))?;
            set_mode(&path, src.exec)?;
            out.push(FileEntry { path: rel.clone(), exec: src.exec, sha256: src.sha256 });
        }
        links.push(Link { path: rel, target });
    }
    Ok(Extracted { files: out, links })
}

/// Resolves a relative link target against the link's directory; `None` if it leaves the archive.
fn resolve(dir: &[String], target: &str) -> Option<String> {
    if target.starts_with('/') || target.contains(['\\', ':', '\0']) {
        return None;
    }
    let mut parts: Vec<&str> = dir.iter().map(String::as_str).collect();
    for p in target.split('/') {
        match p {
            "" | "." => {}
            ".." => {
                parts.pop()?;
            }
            p => parts.push(p),
        }
    }
    Some(parts.join("/"))
}

/// A symlink inside `dir` (`""` = the whole package) that is not a copy of a file in that same
/// directory: those are rejected.
pub fn bad_link_in<'a>(links: &'a [Link], dir: &str) -> Option<&'a Link> {
    let prefix = if dir.is_empty() { String::new() } else { format!("{}/", dir.trim_end_matches('/')) };
    links.iter().filter(|l| l.path.starts_with(&prefix)).find(|l| !l.target.as_ref().is_some_and(|t| t.starts_with(&prefix)))
}

#[cfg(unix)]
fn set_mode(path: &Path, exec: bool) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(if exec { 0o755 } else { 0o644 }))?;
    Ok(())
}

#[cfg(not(unix))]
fn set_mode(_: &Path, _: bool) -> Result<()> {
    Ok(())
}

/// Entries under `dir` (`""` = all) with the prefix removed.
pub fn subtree(entries: &[FileEntry], dir: &str) -> Vec<FileEntry> {
    if dir.is_empty() {
        return entries.to_vec();
    }
    let prefix = format!("{}/", dir.trim_end_matches('/'));
    entries.iter().filter_map(|e| e.path.strip_prefix(&prefix).map(|p| FileEntry { path: p.to_string(), ..e.clone() })).collect()
}

/// Same tree, same bytes: files only, sorted, fixed mtime and permissions.
pub fn zip_dir(dir: &Path) -> Result<Vec<u8>> {
    let mut entries = scan_dir(dir)?;
    entries.sort_by(|a, b| a.path.cmp(&b.path));
    let mut w = ZipWriter::new(Cursor::new(Vec::new()));
    for e in &entries {
        let opts = SimpleFileOptions::DEFAULT
            .compression_method(CompressionMethod::Deflated)
            .compression_level(Some(6))
            .system(System::Unix)
            .unix_permissions(if e.exec { 0o755 } else { 0o644 });
        w.start_file(e.path.as_str(), opts)?;
        w.write_all(&std::fs::read(dir.join(&e.path))?)?;
    }
    Ok(w.finish()?.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::skill::tree_hash;

    enum Item<'a> {
        File(&'a str, u32, &'a [u8]),
        Dir(&'a str),
        Link(&'a str, &'a str),
    }

    fn build(items: &[Item]) -> Vec<u8> {
        let mut w = ZipWriter::new(Cursor::new(Vec::new()));
        for it in items {
            match it {
                Item::File(n, mode, c) => {
                    w.start_file(*n, SimpleFileOptions::DEFAULT.system(System::Unix).unix_permissions(*mode)).unwrap();
                    w.write_all(c).unwrap();
                }
                Item::Dir(n) => w.add_directory(*n, SimpleFileOptions::DEFAULT.system(System::Unix)).unwrap(),
                Item::Link(n, t) => w.add_symlink(*n, *t, SimpleFileOptions::DEFAULT.system(System::Unix)).unwrap(),
            }
        }
        w.finish().unwrap().into_inner()
    }

    fn try_extract(items: &[Item], limits: Limits) -> Result<Vec<FileEntry>> {
        let dir = tempfile::tempdir().unwrap();
        extract(&build(items), dir.path(), &limits).map(|e| e.files)
    }

    #[test]
    fn rejects_attacks() {
        for name in ["../x", "/abs", "a/../../x", "a/..", "c:/x", "a\\..\\x"] {
            let r = try_extract(&[Item::File("ok", 0o644, b"1"), Item::File(name, 0o644, b"x")], Limits::default());
            assert!(r.is_err(), "{name} accepted");
        }
        let dir = tempfile::tempdir().unwrap();
        let items = [
            Item::File("s/SKILL.md", 0o644, b"x"),
            Item::File("s/AGENTS.md", 0o755, b"agents"),
            Item::Link("s/CLAUDE.md", "AGENTS.md"),
            Item::Link("s/evil", "/etc/passwd"),
            Item::Link("t/out", "../s/AGENTS.md"),
            Item::Link("u/esc", "../../x"),
        ];
        let e = extract(&build(&items), dir.path(), &Limits::default()).unwrap();
        let claude = dir.path().join("s/CLAUDE.md");
        assert!(!claude.symlink_metadata().unwrap().file_type().is_symlink(), "links are written as copies");
        assert_eq!(std::fs::read(&claude).unwrap(), b"agents");
        assert!(e.files.iter().any(|f| f.path == "s/CLAUDE.md" && f.exec));
        assert!(!dir.path().join("s/evil").exists() && !dir.path().join("u/esc").exists());
        assert_eq!(bad_link_in(&e.links, "s").map(|l| l.path.as_str()), Some("s/evil"));
        assert_eq!(bad_link_in(&e.links, "t").map(|l| l.path.as_str()), Some("t/out"), "target outside the skill");
        assert!(bad_link_in(&e.links, "other").is_none());
        assert!(bad_link_in(&e.links[..1], "s").is_none());
        let many = [Item::File("a", 0o644, b"1"), Item::File("b", 0o644, b"2"), Item::File("c", 0o644, b"3")];
        assert!(try_extract(&many, Limits { files: 2, ..Limits::default() }).is_err());
        assert!(try_extract(&many, Limits { files: 3, ..Limits::default() }).is_ok());
        let big = vec![0u8; 1000];
        assert!(try_extract(&[Item::File("a", 0o644, &big)], Limits { unpacked: 999, ..Limits::default() }).is_err());
        assert!(try_extract(&[Item::File("a", 0o644, b"x"), Item::Dir("empty/")], Limits::default()).is_err());
        assert!(try_extract(&[Item::File("a", 0o644, b"x"), Item::File("./a", 0o644, b"y")], Limits::default()).is_err());
    }

    #[test]
    fn strips_single_top_dir_only() {
        let e = try_extract(
            &[Item::Dir("repo-abc/"), Item::File("repo-abc/SKILL.md", 0o644, b"s"), Item::File("repo-abc/bin/x", 0o755, b"x")],
            Limits::default(),
        )
        .unwrap();
        let mut paths: Vec<_> = e.iter().map(|e| (e.path.as_str(), e.exec)).collect();
        paths.sort();
        assert_eq!(paths, [("SKILL.md", false), ("bin/x", true)]);
        let e = try_extract(&[Item::File("top/a", 0o644, b"1"), Item::File("b", 0o644, b"2")], Limits::default()).unwrap();
        assert!(e.iter().any(|e| e.path == "top/a"));
        assert_eq!(subtree(&e, "top")[0].path, "a");
        assert_eq!(subtree(&e, "").len(), 2);
    }

    #[test]
    fn zip_dir_is_deterministic_and_round_trips() {
        let make = || {
            let d = tempfile::tempdir().unwrap();
            std::fs::write(d.path().join("SKILL.md"), b"---\nname: x\n---\n").unwrap();
            std::fs::create_dir(d.path().join("scripts")).unwrap();
            std::fs::write(d.path().join("scripts/run.sh"), b"#!/bin/sh\n").unwrap();
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                std::fs::set_permissions(d.path().join("scripts/run.sh"), std::fs::Permissions::from_mode(0o755)).unwrap();
            }
            d
        };
        let a = make();
        std::thread::sleep(std::time::Duration::from_millis(1100));
        let b = make();
        let za = zip_dir(a.path()).unwrap();
        assert_eq!(za, zip_dir(b.path()).unwrap());
        let out = tempfile::tempdir().unwrap();
        let entries = extract(&za, out.path(), &Limits::default()).unwrap().files;
        assert_eq!(tree_hash(&entries), tree_hash(&scan_dir(a.path()).unwrap()));
        assert_eq!(tree_hash(&scan_dir(out.path()).unwrap()), tree_hash(&entries));
    }
}
