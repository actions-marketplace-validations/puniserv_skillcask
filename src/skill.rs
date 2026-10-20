//! SKILL.md frontmatter, skill names and the tree hash.

use std::collections::BTreeMap;
use std::path::Path;

use sha2::{Digest, Sha256};

use crate::bail;
use crate::error::{IO, Result};

pub const SKILL_MD: &str = "SKILL.md";

/// Top-level scalar keys of the YAML frontmatter; nested values are skipped.
pub fn frontmatter(text: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let mut lines = text.lines();
    if lines.next().map(str::trim_end) != Some("---") {
        return out;
    }
    for line in lines {
        if line.trim_end() == "---" {
            break;
        }
        if line.starts_with([' ', '\t', '#', '-']) {
            continue;
        }
        if let Some((k, v)) = line.split_once(':') {
            let v = v.trim();
            let v = v
                .strip_prefix('"')
                .and_then(|v| v.strip_suffix('"'))
                .or_else(|| v.strip_prefix('\'').and_then(|v| v.strip_suffix('\'')))
                .unwrap_or(v);
            if !v.is_empty() {
                out.insert(k.trim().to_string(), v.to_string());
            }
        }
    }
    out
}

/// Sets the frontmatter `name:` value, keeping every other byte. No frontmatter or no `name:`
/// line: unchanged, since the directory name then names the skill.
pub fn rename_frontmatter(text: &str, to: &str) -> String {
    let body = text.strip_prefix('\u{feff}').unwrap_or(text);
    let bom = &text[..text.len() - body.len()];
    let mut lines = body.split_inclusive('\n');
    if lines.next().map(str::trim_end) != Some("---") {
        return text.to_string();
    }
    let mut at = body.find('\n').map_or(body.len(), |i| i + 1);
    for line in lines {
        let content = line.trim_end_matches(['\n', '\r']);
        if content.trim_end() == "---" {
            break;
        }
        if content.starts_with("name:") {
            let eol = &line[content.len()..];
            return format!("{bom}{}name: {to}{eol}{}", &body[..at], &body[at + line.len()..]);
        }
        at += line.len();
    }
    text.to_string()
}

/// `[a-z0-9][a-z0-9-]*`: also the directory name under `.agents/skills/`.
pub fn valid_name(n: &str) -> bool {
    n.starts_with(|c: char| c.is_ascii_lowercase() || c.is_ascii_digit())
        && n.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

#[derive(Clone, Debug, PartialEq)]
pub struct FileEntry {
    /// Relative, `/`-separated.
    pub path: String,
    pub exec: bool,
    pub sha256: String,
}

impl FileEntry {
    pub fn new(path: String, exec: bool, content: &[u8]) -> FileEntry {
        FileEntry { path, exec, sha256: hex::encode(Sha256::digest(content)) }
    }
}

/// sha256 over `<path>\0<mode>\0<sha256 of content>\n` per regular file, sorted by path.
pub fn tree_hash(entries: &[FileEntry]) -> String {
    let mut sorted: Vec<&FileEntry> = entries.iter().collect();
    sorted.sort_by(|a, b| a.path.cmp(&b.path));
    let mut h = Sha256::new();
    for e in sorted {
        h.update(format!("{}\0{}\0{}\n", e.path, if e.exec { "755" } else { "644" }, e.sha256));
    }
    hex::encode(h.finalize())
}

/// Lists regular files under `dir`; symlinks, special files and empty directories are errors.
pub fn scan_dir(dir: &Path) -> Result<Vec<FileEntry>> {
    let mut out = Vec::new();
    scan(dir, "", &mut out)?;
    Ok(out)
}

fn scan(dir: &Path, prefix: &str, out: &mut Vec<FileEntry>) -> Result<()> {
    let mut any = false;
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        any = true;
        let name = entry.file_name().into_string().map_err(|n| crate::error::Error::new(IO, format!("non-UTF-8 file name {n:?}")))?;
        let rel = if prefix.is_empty() { name } else { format!("{prefix}/{name}") };
        let meta = entry.path().symlink_metadata()?;
        let ft = meta.file_type();
        if ft.is_dir() {
            scan(&entry.path(), &rel, out)?;
        } else if ft.is_file() {
            out.push(FileEntry::new(rel, is_exec(&meta), &std::fs::read(entry.path())?));
        } else {
            bail!(IO, "{}: symlinks and special files are not allowed in a skill", rel);
        }
    }
    if !any && !prefix.is_empty() {
        bail!(IO, "{prefix}: empty directories are not allowed in a skill");
    }
    Ok(())
}

#[cfg(unix)]
fn is_exec(m: &std::fs::Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt;
    m.permissions().mode() & 0o111 != 0
}

// No exec bit here; installed modes come from the store's `.skillcask-modes` instead.
#[cfg(not(unix))]
fn is_exec(_: &std::fs::Metadata) -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_frontmatter() {
        let f = frontmatter("---\nname: agents-md\nversion: \"1.2.0\"\ndescription: >\n  multi\nmetadata:\n  a: b\n---\n# body\nname: no");
        assert_eq!(f.get("name").unwrap(), "agents-md");
        assert_eq!(f.get("version").unwrap(), "1.2.0");
        assert!(!f.contains_key("a"));
        assert!(frontmatter("# no frontmatter").is_empty());
        assert!(valid_name("agents-md") && valid_name("a1") && !valid_name("-a") && !valid_name("A") && !valid_name(""));
    }

    #[test]
    fn renames_frontmatter_name_only() {
        let t = "---\nname: code-review\ndescription: name: x\n---\n# name: code-review\n";
        assert_eq!(rename_frontmatter(t, "mp-review"), "---\nname: mp-review\ndescription: name: x\n---\n# name: code-review\n");
        assert_eq!(rename_frontmatter("---\r\nname: \"a\"\r\n---\r\n", "b"), "---\r\nname: b\r\n---\r\n");
        assert_eq!(rename_frontmatter("\u{feff}---\nname: a\n---\n", "b"), "\u{feff}---\nname: b\n---\n");
        let no_name = "---\ndescription: d\n---\nname: a\n";
        assert_eq!(rename_frontmatter(no_name, "b"), no_name);
        let nested = "---\nmetadata:\n  name: x\n---\n";
        assert_eq!(rename_frontmatter(nested, "b"), nested);
        assert_eq!(rename_frontmatter("# no frontmatter", "b"), "# no frontmatter");
        assert_eq!(frontmatter(&rename_frontmatter(t, "mp-review"))["name"], "mp-review");
    }

    #[test]
    fn tree_hash_matches_definition() {
        let e = vec![FileEntry::new("b/x.sh".into(), true, b"x"), FileEntry::new("SKILL.md".into(), false, b"s")];
        let mut h = Sha256::new();
        h.update(format!("SKILL.md\0644\0{}\n", hex::encode(Sha256::digest(b"s"))));
        h.update(format!("b/x.sh\0755\0{}\n", hex::encode(Sha256::digest(b"x"))));
        assert_eq!(tree_hash(&e), hex::encode(h.finalize()));

        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("SKILL.md"), b"s").unwrap();
        std::fs::create_dir(dir.path().join("b")).unwrap();
        std::fs::write(dir.path().join("b/x.sh"), b"x").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(dir.path().join("b/x.sh"), std::fs::Permissions::from_mode(0o755)).unwrap();
            assert_eq!(tree_hash(&scan_dir(dir.path()).unwrap()), tree_hash(&e));
            std::os::unix::fs::symlink("SKILL.md", dir.path().join("l")).unwrap();
            assert!(scan_dir(dir.path()).is_err());
            std::fs::remove_file(dir.path().join("l")).unwrap();
        }
        std::fs::create_dir(dir.path().join("empty")).unwrap();
        assert!(scan_dir(dir.path()).is_err());
    }
}
