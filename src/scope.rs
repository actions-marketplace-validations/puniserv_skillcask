//! Where skillcask reads its manifest and writes skills: a project, or the user's home.

use std::path::{Path, PathBuf};

use crate::bail;
use crate::error::{MANIFEST, Result};

#[derive(Clone, Debug)]
pub struct Scope {
    /// Base of the store and the agent targets: the project root, or home.
    pub root: PathBuf,
    /// Holds skills.toml, skills.lock and auth.json: the project root, or the config dir.
    pub config: PathBuf,
    pub global: bool,
}

impl Scope {
    pub fn project(root: PathBuf) -> Scope {
        Scope { config: root.clone(), root, global: false }
    }

    pub fn global() -> Result<Scope> {
        let Some(home) = home() else { bail!(MANIFEST, "--global needs HOME (or USERPROFILE) to be set") };
        Ok(Scope { config: config_dir_of(&home, |k| std::env::var_os(k)), root: home, global: true })
    }

    /// `rel` (a path under `root`) as the user should read it in messages.
    pub fn show(&self, rel: &str) -> String {
        if self.global { format!("~/{rel}") } else { rel.to_string() }
    }
}

pub fn home() -> Option<PathBuf> {
    std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")).filter(|h| !h.is_empty()).map(PathBuf::from)
}

/// The user's config dir, home of the global manifest and `config.toml`; `None` without a home.
pub fn config_dir() -> Option<PathBuf> {
    home().map(|h| config_dir_of(&h, |k| std::env::var_os(k)))
}

/// `$SKILLCASK_HOME`, else `$XDG_CONFIG_HOME/skillcask`, else `~/.config/skillcask`.
fn config_dir_of(home: &Path, var: impl Fn(&str) -> Option<std::ffi::OsString>) -> PathBuf {
    let set = |k: &str| var(k).filter(|v| !v.is_empty()).map(PathBuf::from);
    set("SKILLCASK_HOME")
        .or_else(|| set("XDG_CONFIG_HOME").map(|x| x.join("skillcask")))
        .unwrap_or_else(|| home.join(".config").join("skillcask"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_dir_precedence() {
        let home = Path::new("/h");
        let env =
            |pairs: &'static [(&'static str, &'static str)]| move |k: &str| pairs.iter().find(|(n, _)| *n == k).map(|(_, v)| v.into());
        assert_eq!(config_dir_of(home, env(&[])), Path::new("/h/.config/skillcask"));
        assert_eq!(config_dir_of(home, env(&[("XDG_CONFIG_HOME", "/x")])), Path::new("/x/skillcask"));
        assert_eq!(config_dir_of(home, env(&[("XDG_CONFIG_HOME", "/x"), ("SKILLCASK_HOME", "/s")])), Path::new("/s"));
        assert_eq!(config_dir_of(home, env(&[("SKILLCASK_HOME", "")])), Path::new("/h/.config/skillcask"));
    }
}
