use std::cell::OnceCell;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::{Component, Path, PathBuf};

use jiff::Timestamp;
use sha1::Sha1;
use sha2::{Digest, Sha256};

use crate::archive::{self, Limits};
use crate::bail;
use crate::error::{Context, Error, HASH, MANIFEST, NETWORK, Result};
use crate::http::Http;
use crate::lock::{Dist, Lock, LockedSkill, Package};
use crate::manifest::{self, Manifest, Repository, SkillReq};
use crate::project::{self, LinkState, STORE};
use crate::registry::{self, Candidate, Registry};
use crate::skill::{self, FileEntry};
use crate::version::{self, Constraint};

pub struct Ctx {
    pub root: PathBuf,
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
    pub fn new(root: PathBuf, verbose: bool, limits: Limits) -> Ctx {
        Ctx { root, verbose, limits, http: OnceCell::new() }
    }

    fn http(&self) -> Result<&Http> {
        if let Some(h) = self.http.get() {
            return Ok(h);
        }
        let h = Http::new(&self.root, self.verbose)?;
        Ok(self.http.get_or_init(|| h))
    }

    fn manifest_or_default(&self) -> Result<Manifest> {
        if self.root.join(manifest::FILE).exists() { Manifest::load(&self.root) } else { manifest::parse(manifest::TEMPLATE) }
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
        let dir = project::temp_dir(&self.root)?;
        let x = archive::extract(&bytes, dir.path(), &self.limits).ctx(name)?;
        Ok((sha, Fetched { dir, entries: x.files, links: x.links }))
    }

    fn resolve(&self, m: &Manifest, req: &SkillReq, prepared: &mut HashMap<String, Fetched>) -> Result<Package> {
        let reg = Registry::new(self.http()?);
        let (repo, cands) = reg.find(&m.repositories, &req.name, req.repository.as_deref())?;
        let c = registry::select(&cands, &req.name, &req.constraint, m.policy.min_release_age, Timestamp::now())?;
        self.lock_candidate(req, &repo, &c, prepared)
    }

    fn lock_candidate(&self, req: &SkillReq, repo: &Repository, c: &Candidate, prepared: &mut HashMap<String, Fetched>) -> Result<Package> {
        let (sha, f) = self.fetch(&c.name, &c.dist, None, c.dist_shasum.as_deref())?;
        let mut skills: Vec<LockedSkill> = Vec::new();
        for p in &c.skill_paths {
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
            let name = skill::frontmatter(&text)
                .remove("name")
                .ok_or_else(|| Error::new(MANIFEST, format!("{} {}: {md} has no frontmatter name", c.name, c.version)))?;
            if !skill::valid_name(&name) {
                bail!(MANIFEST, "{}: skill name {name:?} must match [a-z0-9][a-z0-9-]*", c.name);
            }
            if skills.iter().any(|s| s.name == name) {
                bail!(MANIFEST, "{}: skill name {name:?} appears twice in the package", c.name);
            }
            let tree_sha256 = skill::tree_hash(&f.skill_files(&c.name, &name, &dir)?);
            skills.push(LockedSkill { name, path: dir, tree_sha256 });
        }
        if let Some(sel) = &req.skills {
            for s in sel {
                if !skills.iter().any(|k| &k.name == s) {
                    let have: Vec<&str> = skills.iter().map(|k| k.name.as_str()).collect();
                    bail!(MANIFEST, "{}: no skill {s:?} in {} (it has: {})", req.name, c.version, have.join(", "));
                }
            }
            skills.retain(|k| sel.contains(&k.name));
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
        let root = &self.root;
        for p in m.targets.iter().map(String::as_str).chain([STORE, ".gitignore"]) {
            project::no_symlink(root, p)?;
        }
        let old_managed = project::block_managed(root)?;
        let locked = locked_names(lock)?;
        let locals = project::local_names(root, &m.local)?;
        if let Some(n) = locals.iter().find(|n| locked.contains_key(*n)) {
            bail!(MANIFEST, "skill {n:?} is both a project skill in {} and provided by {}", m.local, locked[n].0.name);
        }
        for (n, (p, s)) in &locked {
            let dir = project::store_dir(root, n);
            if dir.exists() && !old_managed.contains(n) && !installed_ok(root, s) {
                bail!(MANIFEST, "{STORE}/{n} exists and is not managed by skillcask, but {} provides a skill with that name", p.name);
            }
            for t in &m.targets {
                if project::link_state(root, t, STORE, n) == LinkState::Foreign {
                    bail!(MANIFEST, "{t}/{n} exists and was not created by skillcask; move it away");
                }
            }
        }
        Ok(())
    }

    /// Makes disk match the lock: store, links, gitignore block, git index.
    fn materialize(&self, m: &Manifest, lock: &Lock, mut prepared: HashMap<String, Fetched>) -> Result<()> {
        self.preflight(m, lock)?;
        let root = &self.root;
        let old_managed = project::block_managed(root)?;
        let locked = locked_names(lock)?;
        let locals = project::local_names(root, &m.local)?;
        for n in project::stale_local_links(root, &m.local, &locals) {
            if locked.contains_key(&n) || old_managed.contains(&n) {
                continue;
            }
            for t in &m.targets {
                project::unlink(root, t, &n)?;
            }
            project::unlink(root, STORE, &n)?;
        }
        let hand = hand_written(root, lock, &old_managed, &locals)?;

        let mut modes = project::read_modes(root);
        for p in &lock.packages {
            let need: Vec<&LockedSkill> = p.skills.iter().filter(|s| !installed_ok(root, s)).collect();
            if need.is_empty() {
                continue;
            }
            let f = match prepared.remove(&p.name) {
                Some(f) => f,
                None => self.fetch(&p.name, &p.dist, Some(&p.dist_sha256), None)?.1,
            };
            for s in need {
                let files = f.skill_files(&p.name, &s.name, &s.path)?;
                let got = skill::tree_hash(&files);
                if got != s.tree_sha256 {
                    bail!(HASH, "{} {}: skill {} has tree-sha256 {got}, skills.lock expects {}", p.name, p.version, s.name, s.tree_sha256);
                }
                project::place(root, &s.name, &f.dir.path().join(&s.path))?;
                set_modes(&mut modes, &s.name, &files);
                println!("installed {} ({} {})", s.name, p.name, p.version);
            }
        }

        for n in old_managed.iter().filter(|n| !locked.contains_key(*n)) {
            for t in &m.targets {
                project::unlink(root, t, n)?;
            }
            let dir = project::store_dir(root, n);
            if dir.symlink_metadata().is_ok_and(|m| m.file_type().is_symlink()) {
                std::fs::remove_file(&dir)?;
            } else if dir.is_dir() {
                std::fs::remove_dir_all(dir)?;
            }
            set_modes(&mut modes, n, &[]);
            println!("removed {n}");
        }
        project::write_modes(root, &modes)?;

        let mut copies = BTreeSet::new();
        for (at, source, n) in link_plan(m, &locked, &hand, &locals) {
            if project::link(root, &at, source, &n)? && !locked.contains_key(&n) {
                copies.insert(format!("/{at}/{n}"));
            }
        }
        let managed: BTreeSet<String> = locked.keys().cloned().collect();
        project::write_block(root, &project::block_lines(&managed, &m.targets, &copies))?;

        let tracked = project::git_tracked(root, &managed_paths(&managed, &m.targets));
        if !tracked.is_empty() {
            project::git_untrack(root, &tracked)?;
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

fn hand_written(root: &Path, lock: &Lock, old_managed: &BTreeSet<String>, locals: &BTreeSet<String>) -> Result<BTreeSet<String>> {
    let locked: BTreeSet<&str> = lock.skills().map(|(_, s)| s.name.as_str()).collect();
    Ok(project::store_names(root)?
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

fn installed_ok(root: &Path, s: &LockedSkill) -> bool {
    tree_on_disk(root, &s.name).is_some_and(|h| h == s.tree_sha256)
}

fn tree_on_disk(root: &Path, name: &str) -> Option<String> {
    let dir = project::store_dir(root, name);
    let mut entries = skill::scan_dir(&dir).ok().filter(|_| dir.is_dir())?;
    if !cfg!(unix) {
        let modes = project::read_modes(root);
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
            Some(p) if req.repository.as_ref().and_then(|r| m.repository(r)).is_some_and(|r| r.url != p.repository) => {
                Some("repository changed".to_string())
            }
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

pub fn init(ctx: &Ctx) -> Result<()> {
    let path = ctx.root.join(manifest::FILE);
    if path.exists() {
        bail!(MANIFEST, "{} already exists", manifest::FILE);
    }
    std::fs::write(&path, manifest::TEMPLATE)?;
    println!("created {}", manifest::FILE);
    Ok(())
}

pub fn add(ctx: &Ctx, spec: &str, repository: Option<String>) -> Result<()> {
    let (name, constraint) = match spec.split_once('@') {
        Some((n, c)) => (n.to_string(), Some(c.to_string())),
        None => (spec.to_string(), None),
    };
    if !manifest::valid_package_name(&name) {
        bail!(MANIFEST, "{name:?} is not a valid package name (vendor/name, lowercase)");
    }
    let existed = ctx.root.join(manifest::FILE).exists();
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
    let repository = repository.or_else(|| existing.as_ref().and_then(|e| e.repository.clone()));

    let reg = Registry::new(ctx.http()?);
    let (repo, cands) = reg.find(&m.repositories, &name, repository.as_deref())?;
    let c = registry::select(&cands, &name, constraint.as_deref().unwrap_or("*"), m.policy.min_release_age, Timestamp::now())?;
    let constraint = constraint.unwrap_or_else(|| {
        if m.policy.allow_ranges { c.parsed.major_minor() } else { c.version.trim_start_matches(['v', 'V']).to_string() }
    });
    let req = SkillReq { name, constraint, repository, skills: existing.and_then(|e| e.skills) };
    let mut prepared = HashMap::new();
    let pkg = ctx.lock_candidate(&req, &repo, &c, &mut prepared)?;
    let mut lock = Lock::load(&ctx.root)?;
    lock.upsert(pkg);
    ctx.preflight(&m, &lock)?;

    if !existed {
        std::fs::write(ctx.root.join(manifest::FILE), manifest::TEMPLATE)?;
    }
    manifest::write_skill(&ctx.root, &req)?;
    lock.save(&ctx.root)?;
    println!("added {} = {:?} ({})", req.name, req.constraint, c.version);
    ctx.materialize(&Manifest::load(&ctx.root)?, &lock, prepared)
}

pub fn remove(ctx: &Ctx, names: &[String]) -> Result<()> {
    let m = Manifest::load(&ctx.root)?;
    let mut lock = Lock::load(&ctx.root)?;
    for n in names {
        if m.skill(n).is_none() && lock.get(n).is_none() {
            bail!(MANIFEST, "{n} is not in {} or {}", manifest::FILE, crate::lock::FILE);
        }
    }
    manifest::remove_skills(&ctx.root, names)?;
    lock.packages.retain(|p| !names.contains(&p.name));
    lock.save(&ctx.root)?;
    ctx.materialize(&Manifest::load(&ctx.root)?, &lock, HashMap::new())
}

pub fn install(ctx: &Ctx, frozen: bool) -> Result<()> {
    let m = Manifest::load(&ctx.root)?;
    let mut lock = Lock::load(&ctx.root)?;
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
        lock.save(&ctx.root)?;
    }
    ctx.materialize(&m, &lock, prepared)
}

pub fn update(ctx: &Ctx, names: &[String]) -> Result<()> {
    let m = Manifest::load(&ctx.root)?;
    let mut lock = Lock::load(&ctx.root)?;
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
    lock.save(&ctx.root)?;
    ctx.materialize(&m, &lock, prepared)
}

pub fn outdated(ctx: &Ctx) -> Result<()> {
    let m = Manifest::load(&ctx.root)?;
    let lock = Lock::load(&ctx.root)?;
    let reg = Registry::new(ctx.http()?);
    let now = Timestamp::now();
    let mut rows = vec![["package", "locked", "within constraint", "latest", "note"].map(String::from)];
    for req in &m.skills {
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
        rows.push([
            req.name.clone(),
            lock.get(&req.name).map_or("-".into(), |p| p.version.clone()),
            v(within),
            v(registry::newest(&cands, None)),
            note,
        ]);
    }
    print_table(&rows);
    Ok(())
}

pub fn status(ctx: &Ctx) -> Result<()> {
    let m = Manifest::load(&ctx.root)?;
    let lock = Lock::load(&ctx.root)?;
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
                for s in &p.skills {
                    let state = match tree_on_disk(&ctx.root, &s.name) {
                        None => "not installed",
                        Some(h) if h != s.tree_sha256 => "modified",
                        Some(_) => "ok",
                    };
                    row(&mut rows, &p.name, &p.version, &s.name, state);
                }
            }
        }
    }
    for p in lock.packages.iter().filter(|p| m.skill(&p.name).is_none()) {
        row(&mut rows, &p.name, &p.version, "-", "not in skills.toml");
    }
    let locals = project::local_names(&ctx.root, &m.local)?;
    for h in hand_written(&ctx.root, &lock, &project::block_managed(&ctx.root)?, &locals)? {
        row(&mut rows, "-", "-", &h, "hand-written");
    }
    for l in &locals {
        let state = if project::link_state(&ctx.root, STORE, &m.local, l) == LinkState::Ok { "project" } else { "not linked" };
        row(&mut rows, "-", "-", l, state);
    }
    print_table(&rows);
    if bad > 0 {
        bail!(MANIFEST, "{bad} problem(s); run `skillcask install`");
    }
    Ok(())
}

pub fn doctor(ctx: &Ctx, fix: bool) -> Result<()> {
    let root = &ctx.root;
    let m = Manifest::load(root)?;
    let lock = Lock::load(root)?;
    for p in m.targets.iter().map(String::as_str).chain([STORE, ".gitignore"]) {
        project::no_symlink(root, p)?;
    }
    let locked = locked_names(&lock)?;
    let locals = project::local_names(root, &m.local)?;
    let hand = hand_written(root, &lock, &project::block_managed(root)?, &locals)?;
    let mut open = Vec::new();
    let mut fixed = Vec::new();

    let mut copies = BTreeSet::new();
    for (at, source, n) in link_plan(&m, &locked, &hand, &locals) {
        let state = project::link_state(root, &at, source, &n);
        let what = format!("{at}/{n}: link {}", format!("{state:?}").to_lowercase());
        if state != LinkState::Ok {
            if fix && root.join(source).join(&n).is_dir() && state != LinkState::Foreign {
                project::link(root, &at, source, &n)?;
                fixed.push(what);
            } else {
                open.push(what);
            }
        }
        let p = root.join(&at).join(&n);
        if !locked.contains_key(&n) && p.symlink_metadata().is_ok_and(|m| m.is_dir()) {
            copies.insert(format!("/{at}/{n}"));
        }
    }

    let managed: BTreeSet<String> = locked.keys().cloned().collect();
    let tracked = project::git_tracked(root, &managed_paths(&managed, &m.targets));
    if !tracked.is_empty() {
        let what = format!("managed paths committed to git: {}", tracked.join(", "));
        if fix {
            project::git_untrack(root, &tracked)?;
            fixed.push(what);
        } else {
            open.push(what);
        }
    }

    let lines = project::block_lines(&managed, &m.targets, &copies);
    if project::read_block(root)? != lines {
        if fix {
            project::write_block(root, &lines)?;
            fixed.push(".gitignore: stale managed block".into());
        } else {
            open.push(".gitignore: stale managed block".into());
        }
    }

    for (n, (p, s)) in &locked {
        match tree_on_disk(root, n) {
            None => open.push(format!("{STORE}/{n}: not installed ({}); run `skillcask install`", p.name)),
            Some(h) if h != s.tree_sha256 => open.push(format!("{STORE}/{n}: modified ({}); run `skillcask install` to restore", p.name)),
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
            if fix { "" } else { "; `skillcask doctor --fix` repairs links and the gitignore block" }
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
