use std::cell::OnceCell;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::{Component, Path};

use jiff::Timestamp;
use sha1::Sha1;
use sha2::{Digest, Sha256};

use crate::archive::{self, Limits};
use crate::bail;
use crate::error::{Context, Error, HASH, MANIFEST, NETWORK, Result};
use crate::github;
use crate::http::Http;
use crate::lock::{Dist, Lock, LockedSkill, Package};
use crate::manifest::{self, GitHub, Manifest, Repository, SkillReq};
use crate::project::{self, LinkState, STORE};
use crate::registry::{self, Candidate, Registry};
use crate::scope::Scope;
use crate::skill::{self, FileEntry};
use crate::version::{self, Constraint};

pub struct Ctx {
    pub s: Scope,
    pub verbose: bool,
    pub limits: Limits,
    http: OnceCell<Http>,
}

/// A downloaded, verified and unpacked dist, kept so `add`/`update` do not download twice.
struct Fetched {
    dir: tempfile::TempDir,
    entries: Vec<FileEntry>,
    links: Vec<archive::Link>,
}

impl Fetched {
    fn skill_files(&self, package: &str, skill: &str, dir: &str) -> Result<Vec<FileEntry>> {
        if let Some(l) = archive::bad_link_in(&self.links, dir) {
            bail!(
                crate::error::IO,
                "archive: {package}: skill {skill} contains a symlink {} that does not point to a file inside the skill",
                l.path
            );
        }
        Ok(archive::subtree(&self.entries, dir))
    }
}

impl Ctx {
    pub fn new(s: Scope, verbose: bool, limits: Limits) -> Ctx {
        Ctx { s, verbose, limits, http: OnceCell::new() }
    }

    fn http(&self) -> Result<&Http> {
        if let Some(h) = self.http.get() {
            return Ok(h);
        }
        let h = Http::new(&self.s.config, self.verbose)?;
        Ok(self.http.get_or_init(|| h))
    }

    fn manifest_or_default(&self) -> Result<Manifest> {
        if self.s.config.join(manifest::FILE).exists() {
            Manifest::load(&self.s.config, self.s.global)
        } else {
            manifest::parse(manifest::template(self.s.global), self.s.global)
        }
    }

    fn fetch(&self, name: &str, dist: &Dist, expected: Option<&str>, shasum: Option<&str>) -> Result<(String, Fetched)> {
        if dist.kind != "zip" {
            bail!(MANIFEST, "{name}: dist type {:?} is not supported, only zip", dist.kind);
        }
        let bytes = self
            .http()?
            .get(&dist.url, self.limits.download)?
            .ok_or_else(|| Error::new(NETWORK, format!("{name}: dist archive not found (404)")))?;
        let sha = hex::encode(Sha256::digest(&bytes));
        if let Some(exp) = expected
            && exp != sha
        {
            bail!(HASH, "{name}: downloaded archive has sha256 {sha}, skills.lock expects {exp}");
        }
        if let Some(s) = shasum {
            let sha1 = hex::encode(Sha1::digest(&bytes));
            if !s.eq_ignore_ascii_case(&sha1) {
                bail!(HASH, "{name}: downloaded archive has sha1 {sha1}, the repository metadata says {s}");
            }
        }
        let dir = project::temp_dir(&self.s)?;
        let x = archive::extract(&bytes, dir.path(), &self.limits).ctx(name)?;
        Ok((sha, Fetched { dir, entries: x.files, links: x.links }))
    }

    fn resolve(&self, m: &Manifest, req: &SkillReq, prepared: &mut HashMap<String, Fetched>) -> Result<Package> {
        if req.github.is_some() {
            let c = github::resolve(self.http()?, req, m.policy.min_release_age, Timestamp::now())?;
            return self.lock_candidate(req, &github::repository(&req.name), &c, prepared);
        }
        let reg = Registry::new(self.http()?);
        let (repo, cands) = reg.find(&m.repositories, &req.name, req.repository.as_deref())?;
        let c = registry::select(&cands, &req.name, &req.constraint, m.policy.min_release_age, Timestamp::now())?;
        self.lock_candidate(req, &repo, &c, prepared)
    }

    fn lock_candidate(&self, req: &SkillReq, repo: &Repository, c: &Candidate, prepared: &mut HashMap<String, Fetched>) -> Result<Package> {
        let (sha, f) = self.fetch(&c.name, &c.dist, None, c.dist_shasum.as_deref())?;
        // GitHub repositories declare no skill paths; any SKILL.md counts.
        let discovered = c.skill_paths.is_empty();
        let paths = if discovered { github::discover(&f.entries) } else { c.skill_paths.clone() };
        let mut found: Vec<(String, String)> = Vec::new();
        for p in &paths {
            let p = p.trim_start_matches("./").trim_end_matches('/');
            let rel = Path::new(p);
            if p.is_empty() || p.contains('\\') || rel.components().any(|c| !matches!(c, Component::Normal(_))) {
                bail!(MANIFEST, "{}: invalid skill path {p:?} in extra.ai-agent-skill", c.name);
            }
            let (dir, md) = if p.ends_with(".md") {
                (p.rsplit_once('/').map_or("", |(d, _)| d).to_string(), p.to_string())
            } else {
                (p.to_string(), format!("{p}/{}", skill::SKILL_MD))
            };
            let text = std::fs::read_to_string(f.dir.path().join(&md))
                .map_err(|_| Error::new(MANIFEST, format!("{} {}: {md} is missing from the package", c.name, c.version)))?;
            let name = skill::frontmatter(&text).remove("name").filter(|n| skill::valid_name(n));
            // Repositories written for other tools often use a display name; their directory is the id.
            let name = if discovered {
                let base = dir.rsplit('/').next().filter(|d| !d.is_empty()).unwrap_or_else(|| c.name.rsplit('/').next().unwrap_or(""));
                match name.or_else(|| skill::valid_name(base).then(|| base.to_string())) {
                    Some(n) => n,
                    None => {
                        eprintln!("warning: {}: skipping {md}: no valid skill name ([a-z0-9][a-z0-9-]*)", c.name);
                        continue;
                    }
                }
            } else {
                name.ok_or_else(|| {
                    Error::new(MANIFEST, format!("{} {}: {md} has no frontmatter name matching [a-z0-9][a-z0-9-]*", c.name, c.version))
                })?
            };
            found.push((name, dir));
        }
        if let Some(sel) = &req.skills {
            for s in sel {
                if !found.iter().any(|(n, _)| n == s) {
                    let have: Vec<&str> = found.iter().map(|(n, _)| n.as_str()).collect();
                    bail!(MANIFEST, "{}: no skill {s:?} in {} (it has: {})", req.name, c.version, have.join(", "));
                }
            }
            found.retain(|(n, _)| sel.contains(n));
        }
        if found.is_empty() {
            bail!(MANIFEST, "{} {}: no skills found", c.name, c.version);
        }
        let mut skills: Vec<LockedSkill> = Vec::new();
        for (name, dir) in found {
            if let Some(other) = skills.iter().find(|s| s.name == name) {
                bail!(MANIFEST, "{}: skill name {name:?} appears twice in the package ({} and {dir})", c.name, other.path);
            }
            let tree_sha256 = skill::tree_hash(&f.skill_files(&c.name, &name, &dir)?);
            skills.push(LockedSkill { name, path: dir, tree_sha256 });
        }
        skills.sort_by(|a, b| a.name.cmp(&b.name));
        prepared.insert(c.name.clone(), f);
        Ok(Package {
            name: c.name.clone(),
            constraint: req.constraint.clone(),
            version: c.version.clone(),
            repository: repo.url.clone(),
            dist: c.dist.clone(),
            dist_sha256: sha,
            released: c.time,
            skills,
        })
    }

    /// Conflicts that would stop `materialize`, checked before `add` writes skills.toml and skills.lock.
    fn preflight(&self, m: &Manifest, lock: &Lock) -> Result<()> {
        let s = &self.s;
        for p in m.targets.iter().map(String::as_str).chain([STORE, ".gitignore"]) {
            project::no_symlink(s, p)?;
        }
        let old_managed = project::block_managed(s)?;
        let locked = locked_names(lock)?;
        let locals = project::local_names(s, &m.local)?;
        if let Some(n) = locals.iter().find(|n| locked.contains_key(*n)) {
            bail!(MANIFEST, "skill {n:?} is both a project skill in {} and provided by {}", m.local, locked[n].0.name);
        }
        for (n, (p, sk)) in &locked {
            let dir = project::store_dir(s, n);
            if dir.exists() && !old_managed.contains(n) && !installed_ok(s, sk) {
                bail!(
                    MANIFEST,
                    "{} exists and is not managed by skillcask, but {} provides a skill with that name",
                    s.show(&format!("{STORE}/{n}")),
                    p.name
                );
            }
            for t in &m.targets {
                if not_ours(s, t, n, &project::link_state(s, t, STORE, n), &old_managed) {
                    bail!(MANIFEST, "{} exists and was not created by skillcask; move it away", s.show(&format!("{t}/{n}")));
                }
            }
        }
        Ok(())
    }

    /// Makes disk match the lock: store, links, gitignore block, git index.
    fn materialize(&self, m: &Manifest, lock: &Lock, mut prepared: HashMap<String, Fetched>) -> Result<()> {
        self.preflight(m, lock)?;
        let s = &self.s;
        let old_managed = project::block_managed(s)?;
        let locked = locked_names(lock)?;
        let locals = project::local_names(s, &m.local)?;
        for n in project::stale_local_links(s, &m.local, &locals) {
            if locked.contains_key(&n) || old_managed.contains(&n) {
                continue;
            }
            for t in &m.targets {
                project::unlink(s, t, &n)?;
            }
            project::unlink(s, STORE, &n)?;
        }
        let hand = hand_written(s, lock, &old_managed, &locals)?;

        let mut modes = project::read_modes(s);
        for p in &lock.packages {
            let need: Vec<&LockedSkill> = p.skills.iter().filter(|sk| !installed_ok(s, sk)).collect();
            if need.is_empty() {
                continue;
            }
            let f = match prepared.remove(&p.name) {
                Some(f) => f,
                None => self.fetch(&p.name, &p.dist, Some(&p.dist_sha256), None)?.1,
            };
            for sk in need {
                let files = f.skill_files(&p.name, &sk.name, &sk.path)?;
                let got = skill::tree_hash(&files);
                if got != sk.tree_sha256 {
                    bail!(
                        HASH,
                        "{} {}: skill {} has tree-sha256 {got}, skills.lock expects {}",
                        p.name,
                        p.version,
                        sk.name,
                        sk.tree_sha256
                    );
                }
                project::place(s, &sk.name, &f.dir.path().join(&sk.path))?;
                set_modes(&mut modes, &sk.name, &files);
                println!("installed {} ({} {})", sk.name, p.name, p.version);
            }
        }

        for n in old_managed.iter().filter(|n| !locked.contains_key(*n)) {
            for t in &m.targets {
                project::unlink(s, t, n)?;
            }
            let dir = project::store_dir(s, n);
            if dir.symlink_metadata().is_ok_and(|m| m.file_type().is_symlink()) {
                std::fs::remove_file(&dir)?;
            } else if dir.is_dir() {
                std::fs::remove_dir_all(dir)?;
            }
            set_modes(&mut modes, n, &[]);
            println!("removed {n}");
        }
        project::write_modes(s, &modes)?;

        let mut copies = BTreeSet::new();
        for (at, source, n) in link_plan(m, &locked, &hand, &locals) {
            if project::link(s, &at, source, &n)? && !locked.contains_key(&n) {
                copies.insert(format!("/{at}/{n}"));
            }
        }
        let managed: BTreeSet<String> = locked.keys().cloned().collect();
        project::write_block(s, &project::block_lines(&managed, &m.targets, &copies))?;

        let tracked = project::git_tracked(s, &managed_paths(&managed, &m.targets));
        if !tracked.is_empty() {
            project::git_untrack(s, &tracked)?;
            eprintln!("warning: removed managed paths from the git index (files kept): {}", tracked.join(", "));
        }
        Ok(())
    }
}

fn locked_names(lock: &Lock) -> Result<BTreeMap<String, (&Package, &LockedSkill)>> {
    let mut out: BTreeMap<String, (&Package, &LockedSkill)> = BTreeMap::new();
    for (p, s) in lock.skills() {
        if let Some((other, _)) = out.insert(s.name.clone(), (p, s)) {
            bail!(MANIFEST, "skill {:?} is provided by both {} and {}", s.name, other.name, p.name);
        }
    }
    Ok(out)
}

/// A target entry skillcask must neither replace nor repair.
fn not_ours(s: &Scope, at: &str, n: &str, state: &LinkState, old_managed: &BTreeSet<String>) -> bool {
    match state {
        LinkState::Foreign => true,
        // In home a symlink skillcask did not make belongs to the user or another tool.
        LinkState::Wrong => {
            s.global && !old_managed.contains(n) && s.root.join(at).join(n).symlink_metadata().is_ok_and(|m| m.file_type().is_symlink())
        }
        _ => false,
    }
}

fn hand_written(s: &Scope, lock: &Lock, old_managed: &BTreeSet<String>, locals: &BTreeSet<String>) -> Result<BTreeSet<String>> {
    if s.global {
        return Ok(BTreeSet::new());
    }
    let locked: BTreeSet<&str> = lock.skills().map(|(_, sk)| sk.name.as_str()).collect();
    Ok(project::store_names(s)?
        .into_iter()
        .filter(|n| !locked.contains(n.as_str()) && !old_managed.contains(n) && !locals.contains(n))
        .collect())
}

/// Every link as (directory, source directory, name): project skills into the store, then all
/// skills from the store into each agent target.
fn link_plan<'a>(
    m: &'a Manifest,
    locked: &BTreeMap<String, (&Package, &LockedSkill)>,
    hand: &BTreeSet<String>,
    locals: &BTreeSet<String>,
) -> Vec<(String, &'a str, String)> {
    let mut plan: Vec<(String, &str, String)> = locals.iter().map(|n| (STORE.to_string(), m.local.as_str(), n.clone())).collect();
    for n in locked.keys().chain(hand).chain(locals) {
        plan.extend(m.targets.iter().map(|t| (t.clone(), STORE, n.clone())));
    }
    plan
}

fn installed_ok(s: &Scope, sk: &LockedSkill) -> bool {
    tree_on_disk(s, &sk.name).is_some_and(|h| h == sk.tree_sha256)
}

fn tree_on_disk(s: &Scope, name: &str) -> Option<String> {
    let dir = project::store_dir(s, name);
    let mut entries = skill::scan_dir(&dir).ok().filter(|_| dir.is_dir())?;
    if !cfg!(unix) {
        let modes = project::read_modes(s);
        for e in &mut entries {
            e.exec = modes.contains(&format!("{name}/{}", e.path));
        }
    }
    Some(skill::tree_hash(&entries))
}

fn set_modes(modes: &mut BTreeSet<String>, name: &str, files: &[FileEntry]) {
    let prefix = format!("{name}/");
    modes.retain(|l| !l.starts_with(&prefix));
    modes.extend(files.iter().filter(|f| f.exec).map(|f| format!("{prefix}{}", f.path)));
}

fn managed_paths(managed: &BTreeSet<String>, targets: &[String]) -> Vec<String> {
    managed.iter().flat_map(|n| std::iter::once(format!("{STORE}/{n}")).chain(targets.iter().map(move |t| format!("{t}/{n}")))).collect()
}

/// Manifest entries that need resolving, lock entries to drop, and why.
fn reconcile(m: &Manifest, lock: &Lock) -> (Vec<SkillReq>, Vec<String>, Vec<String>) {
    let (mut needs, mut stale, mut why) = (Vec::new(), Vec::new(), Vec::new());
    for req in &m.skills {
        let reason = match lock.get(&req.name) {
            None => Some("not in skills.lock".to_string()),
            Some(p) if p.constraint != req.constraint => {
                Some(format!("constraint changed from {:?} to {:?}", p.constraint, req.constraint))
            }
            Some(p) if source_changed(m, req, p) => Some("repository changed".to_string()),
            // ponytail: removing `skills = [...]` does not re-resolve to all skills; run `update` for that.
            Some(p)
                if req.skills.as_ref().is_some_and(|sel| {
                    let a: BTreeSet<&String> = sel.iter().collect();
                    let b: BTreeSet<&String> = p.skills.iter().map(|s| &s.name).collect();
                    a != b
                }) =>
            {
                Some("skill selection changed".to_string())
            }
            Some(_) => None,
        };
        if let Some(r) = reason {
            why.push(format!("{}: {r}", req.name));
            needs.push(req.clone());
        }
    }
    for p in &lock.packages {
        if m.skill(&p.name).is_none() {
            why.push(format!("{}: in skills.lock but not in skills.toml", p.name));
            stale.push(p.name.clone());
        }
    }
    (needs, stale, why)
}

fn source_changed(m: &Manifest, req: &SkillReq, p: &Package) -> bool {
    match (req.github, &req.repository) {
        (Some(_), _) => p.repository != github::repository(&req.name).url,
        (None, Some(r)) => m.repository(r).is_some_and(|r| r.url != p.repository),
        (None, None) => github::is_github(&p.repository),
    }
}

pub fn init(ctx: &Ctx) -> Result<()> {
    let path = ctx.s.config.join(manifest::FILE);
    if path.exists() {
        bail!(MANIFEST, "{} already exists", manifest::FILE);
    }
    std::fs::create_dir_all(&ctx.s.config)?;
    std::fs::write(&path, manifest::template(ctx.s.global))?;
    println!("created {}", manifest::FILE);
    Ok(())
}

pub fn add(ctx: &Ctx, spec: &str, repository: Option<String>) -> Result<()> {
    if let Some(rest) = spec.strip_prefix("github:") {
        if repository.is_some() {
            bail!(MANIFEST, "--repository does not apply to github: sources");
        }
        return add_github(ctx, rest);
    }
    let (name, constraint) = match spec.split_once('@') {
        Some((n, c)) => (n.to_string(), Some(c.to_string())),
        None => (spec.to_string(), None),
    };
    if !manifest::valid_package_name(&name) {
        bail!(MANIFEST, "{name:?} is not a valid package name (vendor/name, lowercase)");
    }
    let existed = ctx.s.config.join(manifest::FILE).exists();
    let m = ctx.manifest_or_default()?;
    if let Some(r) = &repository
        && m.repository(r).is_none()
    {
        bail!(MANIFEST, "unknown repository {r:?}; declare it under [repositories] in {}", manifest::FILE);
    }
    if let Some(c) = &constraint {
        Constraint::parse(c).map_err(|e| Error::new(MANIFEST, e))?;
        if !m.policy.allow_ranges && !version::is_exact(c) {
            bail!(MANIFEST, "policy.allow-ranges = false requires an exact version, got {c:?}");
        }
    }
    let existing = m.skill(&name).cloned();
    if existing.as_ref().is_some_and(|e| e.github.is_some()) && repository.is_none() {
        return add_github(ctx, spec);
    }
    let repository = repository.or_else(|| existing.as_ref().and_then(|e| e.repository.clone()));

    let reg = Registry::new(ctx.http()?);
    let (repo, cands) = reg.find(&m.repositories, &name, repository.as_deref())?;
    let c = registry::select(&cands, &name, constraint.as_deref().unwrap_or("*"), m.policy.min_release_age, Timestamp::now())?;
    let constraint = constraint.unwrap_or_else(|| {
        if m.policy.allow_ranges { c.parsed.major_minor() } else { c.version.trim_start_matches(['v', 'V']).to_string() }
    });
    let req = SkillReq { name, constraint, repository, skills: existing.and_then(|e| e.skills), github: None };
    finish_add(ctx, existed, &m, &req, &repo, &c)
}

/// `owner/repo[/skill][@constraint-or-ref]`, the form skills.sh shows as `owner/repo/skill`.
fn add_github(ctx: &Ctx, spec: &str) -> Result<()> {
    let (path, at) = match spec.split_once('@') {
        Some((p, a)) => (p, Some(a.to_string())),
        None => (spec, None),
    };
    let mut parts = path.splitn(3, '/');
    let name = format!("{}/{}", parts.next().unwrap_or(""), parts.next().unwrap_or("")).to_lowercase();
    if !manifest::valid_package_name(&name) {
        bail!(MANIFEST, "{spec:?}: expected github:owner/repo[/skill][@version-or-ref]");
    }
    let skill = parts.next().map(String::from);
    if let Some(s) = &skill
        && !skill::valid_name(s)
    {
        bail!(MANIFEST, "{s:?} is not a valid skill name ([a-z0-9][a-z0-9-]*)");
    }
    let existed = ctx.s.config.join(manifest::FILE).exists();
    let m = ctx.manifest_or_default()?;
    let existing = m.skill(&name).filter(|e| e.github.is_some()).cloned();
    let skills = match (skill, existing.as_ref().map(|e| e.skills.clone())) {
        (None, have) => have.flatten(),
        // Already installs every skill of the repository.
        (Some(_), Some(None)) => None,
        (Some(s), Some(Some(mut have))) => {
            if !have.contains(&s) {
                have.push(s);
            }
            Some(have)
        }
        (Some(s), None) => Some(vec![s]),
    };
    let (given, mode) = match (at, &existing) {
        (Some(a), _) => {
            let mode = if Constraint::parse(&a).is_ok() { GitHub::Tags } else { GitHub::Ref };
            (Some(a), mode)
        }
        (None, Some(e)) => (Some(e.constraint.clone()), e.github.expect("filtered to GitHub entries")),
        (None, None) if github::tags(ctx.http()?, &name)?.is_empty() => (None, GitHub::Ref),
        (None, None) => (None, GitHub::Tags),
    };
    let any = if mode == GitHub::Tags { "*" } else { manifest::DEFAULT_REF };
    let mut req = SkillReq { name, constraint: given.clone().unwrap_or_else(|| any.into()), repository: None, skills, github: Some(mode) };
    if given.is_some() {
        manifest::check_constraint(&req, &m.policy).map_err(|e| Error::new(MANIFEST, format!("{}: {e}", req.name)))?;
    }
    let c = github::resolve(ctx.http()?, &req, m.policy.min_release_age, Timestamp::now())?;
    if given.is_none() {
        req.constraint = match (mode, m.policy.allow_ranges) {
            (GitHub::Tags, true) => c.parsed.major_minor(),
            (GitHub::Tags, false) => c.version.trim_start_matches(['v', 'V']).to_string(),
            (GitHub::Ref, true) => manifest::DEFAULT_REF.into(),
            (GitHub::Ref, false) => c.dist.reference.clone().expect("GitHub candidates carry their sha"),
        };
    }
    finish_add(ctx, existed, &m, &req, &github::repository(&req.name), &c)
}

fn finish_add(ctx: &Ctx, existed: bool, m: &Manifest, req: &SkillReq, repo: &Repository, c: &Candidate) -> Result<()> {
    let mut prepared = HashMap::new();
    let pkg = ctx.lock_candidate(req, repo, c, &mut prepared)?;
    let mut lock = Lock::load(&ctx.s.config)?;
    lock.upsert(pkg);
    ctx.preflight(m, &lock)?;

    if !existed {
        std::fs::create_dir_all(&ctx.s.config)?;
        std::fs::write(ctx.s.config.join(manifest::FILE), manifest::template(ctx.s.global))?;
    }
    manifest::write_skill(&ctx.s.config, req)?;
    lock.save(&ctx.s.config)?;
    println!("added {} = {:?} ({})", req.name, req.constraint, c.version);
    ctx.materialize(&Manifest::load(&ctx.s.config, ctx.s.global)?, &lock, prepared)
}

pub fn remove(ctx: &Ctx, names: &[String]) -> Result<()> {
    let m = Manifest::load(&ctx.s.config, ctx.s.global)?;
    let mut lock = Lock::load(&ctx.s.config)?;
    for n in names {
        if m.skill(n).is_none() && lock.get(n).is_none() {
            bail!(MANIFEST, "{n} is not in {} or {}", manifest::FILE, crate::lock::FILE);
        }
    }
    manifest::remove_skills(&ctx.s.config, names)?;
    lock.packages.retain(|p| !names.contains(&p.name));
    lock.save(&ctx.s.config)?;
    ctx.materialize(&Manifest::load(&ctx.s.config, ctx.s.global)?, &lock, HashMap::new())
}

pub fn install(ctx: &Ctx, frozen: bool) -> Result<()> {
    let m = Manifest::load(&ctx.s.config, ctx.s.global)?;
    let mut lock = Lock::load(&ctx.s.config)?;
    let (needs, stale, why) = reconcile(&m, &lock);
    let mut prepared = HashMap::new();
    if !why.is_empty() {
        if frozen {
            bail!(
                MANIFEST,
                "skills.lock is out of date with skills.toml (frozen install):\n  {}\nrun `skillcask install` locally and commit skills.lock",
                why.join("\n  ")
            );
        }
        for req in &needs {
            lock.upsert(ctx.resolve(&m, req, &mut prepared)?);
        }
        lock.packages.retain(|p| !stale.contains(&p.name));
        locked_names(&lock)?;
        lock.save(&ctx.s.config)?;
    }
    ctx.materialize(&m, &lock, prepared)
}

pub fn update(ctx: &Ctx, names: &[String]) -> Result<()> {
    let m = Manifest::load(&ctx.s.config, ctx.s.global)?;
    let mut lock = Lock::load(&ctx.s.config)?;
    for n in names {
        if m.skill(n).is_none() {
            bail!(MANIFEST, "{n} is not in {}", manifest::FILE);
        }
    }
    let mut prepared = HashMap::new();
    for req in m.skills.iter().filter(|r| names.is_empty() || names.contains(&r.name)) {
        let new = ctx.resolve(&m, req, &mut prepared)?;
        match lock.get(&req.name) {
            Some(old) if old.version == new.version && old.dist_sha256 == new.dist_sha256 => {}
            Some(old) => println!("updated {} {} -> {}", new.name, old.version, new.version),
            None => println!("locked {} {}", new.name, new.version),
        }
        lock.upsert(new);
    }
    let (_, stale, _) = reconcile(&m, &lock);
    lock.packages.retain(|p| !stale.contains(&p.name));
    locked_names(&lock)?;
    lock.save(&ctx.s.config)?;
    ctx.materialize(&m, &lock, prepared)
}

pub fn outdated(ctx: &Ctx) -> Result<()> {
    let m = Manifest::load(&ctx.s.config, ctx.s.global)?;
    let lock = Lock::load(&ctx.s.config)?;
    let reg = Registry::new(ctx.http()?);
    let now = Timestamp::now();
    let mut rows = vec![["package", "locked", "within constraint", "latest", "note"].map(String::from)];
    for req in &m.skills {
        let locked = lock.get(&req.name).map_or("-".into(), |p| p.version.clone());
        if req.github.is_some() {
            let (within, latest) = github::newest(ctx.http()?, req)?;
            let dash = |v: Option<String>| v.unwrap_or_else(|| "-".into());
            rows.push([req.name.clone(), locked, dash(within), dash(latest), String::new()]);
            continue;
        }
        let (_, cands) = reg.find(&m.repositories, &req.name, req.repository.as_deref())?;
        let c = Constraint::parse(&req.constraint).map_err(|e| Error::new(MANIFEST, e))?;
        let within = registry::newest(&cands, Some(&c));
        let note = match within.and_then(|w| w.time.map(|t| (w, t))) {
            Some((w, t)) if t > now - m.policy.min_release_age => {
                format!("{} eligible {}", w.version, (t + m.policy.min_release_age).round(jiff::Unit::Second).unwrap_or(t))
            }
            _ => String::new(),
        };
        let v = |c: Option<&Candidate>| c.map_or("-".to_string(), |c| c.version.clone());
        rows.push([req.name.clone(), locked, v(within), v(registry::newest(&cands, None)), note]);
    }
    print_table(&rows);
    Ok(())
}

pub fn status(ctx: &Ctx) -> Result<()> {
    let m = Manifest::load(&ctx.s.config, ctx.s.global)?;
    let lock = Lock::load(&ctx.s.config)?;
    let mut rows = vec![["package", "version", "skill", "state"].map(String::from)];
    let mut bad = 0;
    let mut row = |rows: &mut Vec<[String; 4]>, p: &str, v: &str, s: &str, state: &str| {
        if !matches!(state, "ok" | "hand-written" | "project") {
            bad += 1;
        }
        rows.push([p, v, s, state].map(String::from));
    };
    for req in &m.skills {
        match lock.get(&req.name) {
            None => row(&mut rows, &req.name, "-", "-", "not locked"),
            Some(p) if p.constraint != req.constraint => row(&mut rows, &req.name, &p.version, "-", "constraint changed"),
            Some(p) => {
                for sk in &p.skills {
                    let state = match tree_on_disk(&ctx.s, &sk.name) {
                        None => "not installed",
                        Some(h) if h != sk.tree_sha256 => "modified",
                        Some(_) => "ok",
                    };
                    row(&mut rows, &p.name, &p.version, &sk.name, state);
                }
            }
        }
    }
    for p in lock.packages.iter().filter(|p| m.skill(&p.name).is_none()) {
        row(&mut rows, &p.name, &p.version, "-", "not in skills.toml");
    }
    let locals = project::local_names(&ctx.s, &m.local)?;
    for h in hand_written(&ctx.s, &lock, &project::block_managed(&ctx.s)?, &locals)? {
        row(&mut rows, "-", "-", &h, "hand-written");
    }
    for l in &locals {
        let state = if project::link_state(&ctx.s, STORE, &m.local, l) == LinkState::Ok { "project" } else { "not linked" };
        row(&mut rows, "-", "-", l, state);
    }
    print_table(&rows);
    if bad > 0 {
        bail!(MANIFEST, "{bad} problem(s); run `skillcask install`");
    }
    Ok(())
}

pub fn doctor(ctx: &Ctx, fix: bool) -> Result<()> {
    let s = &ctx.s;
    let m = Manifest::load(&s.config, s.global)?;
    let lock = Lock::load(&s.config)?;
    for p in m.targets.iter().map(String::as_str).chain([STORE, ".gitignore"]) {
        project::no_symlink(s, p)?;
    }
    let locked = locked_names(&lock)?;
    let locals = project::local_names(s, &m.local)?;
    let old_managed = project::block_managed(s)?;
    let hand = hand_written(s, &lock, &old_managed, &locals)?;
    let mut open = Vec::new();
    let mut fixed = Vec::new();

    let mut copies = BTreeSet::new();
    for (at, source, n) in link_plan(&m, &locked, &hand, &locals) {
        let state = project::link_state(s, &at, source, &n);
        let what = format!("{}: link {}", s.show(&format!("{at}/{n}")), format!("{state:?}").to_lowercase());
        if state != LinkState::Foreign && not_ours(s, &at, &n, &state, &old_managed) {
            open.push(format!("{} exists and was not created by skillcask; move it away", s.show(&format!("{at}/{n}"))));
        } else if state != LinkState::Ok {
            if fix && s.root.join(source).join(&n).is_dir() && state != LinkState::Foreign {
                project::link(s, &at, source, &n)?;
                fixed.push(what);
            } else {
                open.push(what);
            }
        }
        let p = s.root.join(&at).join(&n);
        if !locked.contains_key(&n) && p.symlink_metadata().is_ok_and(|m| m.is_dir()) {
            copies.insert(format!("/{at}/{n}"));
        }
    }

    let managed: BTreeSet<String> = locked.keys().cloned().collect();
    let tracked = project::git_tracked(s, &managed_paths(&managed, &m.targets));
    if !tracked.is_empty() {
        let what = format!("managed paths committed to git: {}", tracked.join(", "));
        if fix {
            project::git_untrack(s, &tracked)?;
            fixed.push(what);
        } else {
            open.push(what);
        }
    }

    let block_file = if s.global { s.config.join("installed").display().to_string() } else { ".gitignore".into() };
    let lines = project::block_lines(&managed, &m.targets, &copies);
    if project::read_block(s)? != lines {
        let what = format!("{block_file}: stale managed block");
        if fix {
            project::write_block(s, &lines)?;
            fixed.push(what);
        } else {
            open.push(what);
        }
    }

    for (n, (p, sk)) in &locked {
        match tree_on_disk(s, n) {
            None => open.push(format!("{}: not installed ({}); run `skillcask install`", s.show(&format!("{STORE}/{n}")), p.name)),
            Some(h) if h != sk.tree_sha256 => {
                open.push(format!("{}: modified ({}); run `skillcask install` to restore", s.show(&format!("{STORE}/{n}")), p.name))
            }
            Some(_) => {}
        }
    }

    for f in &fixed {
        println!("fixed: {f}");
    }
    for o in &open {
        println!("problem: {o}");
    }
    if !open.is_empty() {
        bail!(
            MANIFEST,
            "{} problem(s){}",
            open.len(),
            if fix {
                String::new()
            } else if s.global {
                format!("; `skillcask doctor --fix` repairs links and {block_file}")
            } else {
                "; `skillcask doctor --fix` repairs links and the gitignore block".into()
            }
        );
    }
    if fixed.is_empty() {
        println!("no problems found");
    }
    Ok(())
}

pub fn search(ctx: &Ctx, query: &str) -> Result<()> {
    let m = ctx.manifest_or_default()?;
    let results = Registry::new(ctx.http()?).search(&m.repositories, query)?;
    if results.is_empty() {
        println!("no skill packages match {query:?}");
    }
    let width = results.iter().map(|(n, _)| n.len()).max().unwrap_or(0);
    for (n, d) in results {
        println!("{n:width$}  {d}");
    }
    Ok(())
}

fn print_table<const N: usize>(rows: &[[String; N]]) {
    let mut w = [0; N];
    for r in rows {
        for (i, c) in r.iter().enumerate() {
            w[i] = w[i].max(c.len());
        }
    }
    for r in rows {
        let line: Vec<String> = r.iter().enumerate().map(|(i, c)| format!("{c:w$}", w = w[i])).collect();
        println!("{}", line.join("  ").trim_end());
    }
}
