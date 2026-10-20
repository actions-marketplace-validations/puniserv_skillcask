mod archive;
mod commands;
mod error;
mod github;
mod http;
mod lock;
mod manifest;
mod project;
mod publish;
mod registry;
mod scope;
mod skill;
mod version;

use std::ffi::OsString;
use std::path::PathBuf;

use clap::{Parser, Subcommand};

use crate::archive::Limits;
use crate::commands::Ctx;
use crate::error::{Error, MANIFEST};
use crate::scope::Scope;

const VERSION: &str = concat!(env!("CARGO_PKG_VERSION"), " (", env!("SKILLCASK_COMMIT"), ")");

/// A lockfile-first package manager for AI agent skills.
#[derive(Parser)]
#[command(name = "skillcask", version = VERSION)]
struct Cli {
    /// Print every HTTP request (credentials are never printed).
    #[arg(short, long, global = true)]
    verbose: bool,
    /// Maximum download size, e.g. 50M.
    #[arg(long, global = true, value_parser = parse_size)]
    max_download: Option<u64>,
    /// Maximum unpacked size of one archive, e.g. 100M.
    #[arg(long, global = true, value_parser = parse_size)]
    max_unpacked: Option<u64>,
    /// Maximum number of files in one archive.
    #[arg(long, global = true)]
    max_files: Option<usize>,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Create skills.toml with defaults.
    Init,
    /// Resolve a package, add it to skills.toml and skills.lock, install it.
    Add {
        /// vendor/name[@constraint], or github:owner/repo[/skill][@version-or-ref]
        package: String,
        /// Repository name from [repositories].
        #[arg(long)]
        repository: Option<String>,
    },
    /// Remove packages from skills.toml and skills.lock, with their files and links.
    Remove {
        #[arg(required = true)]
        packages: Vec<String>,
    },
    /// Install exactly what skills.lock pins.
    Install {
        /// Fail instead of resolving when skills.lock does not match skills.toml (implied by CI).
        #[arg(long)]
        frozen: bool,
    },
    /// Re-resolve within constraints and rewrite skills.lock.
    Update { packages: Vec<String> },
    /// Show newer versions per package.
    Outdated,
    /// Compare skills.toml, skills.lock and installed files; exit 1 on any mismatch.
    Status,
    /// Check links, the gitignore block and installed files.
    Doctor {
        /// Repair links, the git index and the gitignore block (never downloads).
        #[arg(long)]
        fix: bool,
    },
    /// Search for skill packages.
    Search { query: String },
    /// Build a static Composer repository from SKILL.md files in a monorepo.
    Publish {
        #[arg(long)]
        vendor: String,
        /// Public https:// URL the output directory will be served from.
        #[arg(long)]
        base_url: Option<String>,
        /// Dist URL template with {vendor}, {name} and {version}.
        #[arg(long)]
        dist_url: Option<String>,
        /// Write all packages into packages.json instead of metadata-url and p2/.
        #[arg(long)]
        inline: bool,
        #[arg(long)]
        out: PathBuf,
        paths: Vec<PathBuf>,
    },
    /// Any other command runs `skillcask-<command>` from PATH, like git and cargo plugins.
    #[command(external_subcommand)]
    External(Vec<OsString>),
}

fn parse_size(s: &str) -> Result<u64, String> {
    let s = s.trim();
    let (num, mult) = match s.char_indices().last() {
        Some((i, 'K' | 'k')) => (&s[..i], 1 << 10),
        Some((i, 'M' | 'm')) => (&s[..i], 1 << 20),
        Some((i, 'G' | 'g')) => (&s[..i], 1 << 30),
        _ => (s, 1),
    };
    num.parse::<u64>().map(|n| n * mult).map_err(|_| format!("invalid size {s:?}, use e.g. 50M"))
}

fn ci() -> bool {
    std::env::var("CI").is_ok_and(|v| !v.is_empty() && v != "0" && !v.eq_ignore_ascii_case("false"))
}

fn run(cli: Cli) -> Result<(), Error> {
    let d = Limits::default();
    let limits = Limits {
        download: cli.max_download.unwrap_or(d.download),
        unpacked: cli.max_unpacked.unwrap_or(d.unpacked),
        files: cli.max_files.unwrap_or(d.files),
    };
    if let Cmd::External(args) = &cli.cmd {
        return plugin(args);
    }
    let root = match cli.cmd {
        Cmd::Init | Cmd::Publish { .. } => std::env::current_dir()?,
        _ => project::find_root()?,
    };
    let ctx = Ctx::new(Scope::project(root), cli.verbose, limits);
    match cli.cmd {
        Cmd::Init => commands::init(&ctx),
        Cmd::Add { package, repository } => commands::add(&ctx, &package, repository),
        Cmd::Remove { packages } => commands::remove(&ctx, &packages),
        Cmd::Install { frozen } => commands::install(&ctx, frozen || ci()),
        Cmd::Update { packages } => commands::update(&ctx, &packages),
        Cmd::Outdated => commands::outdated(&ctx),
        Cmd::Status => commands::status(&ctx),
        Cmd::Doctor { fix } => commands::doctor(&ctx, fix),
        Cmd::Search { query } => commands::search(&ctx, &query),
        Cmd::External(_) => unreachable!("handled above"),
        Cmd::Publish { vendor, base_url, dist_url, inline, out, paths } => {
            if vendor.is_empty() {
                return Err(Error::new(MANIFEST, "--vendor must not be empty"));
            }
            publish::publish(&publish::PublishArgs { vendor, base_url, dist_url, inline, out, paths })
        }
    }
}

/// Runs a user-installed `skillcask-<name>` executable. Packages never provide these.
fn plugin(args: &[OsString]) -> Result<(), Error> {
    let name = args[0].to_string_lossy();
    // A separator would make Command run a path relative to the cwd instead of searching PATH.
    if name.contains(['/', '\\']) {
        return Err(Error::new(MANIFEST, format!("unknown command {name:?}")));
    }
    let exe = format!("skillcask-{name}");
    let status = std::process::Command::new(&exe).args(&args[1..]).status().map_err(|e| {
        if e.kind() == std::io::ErrorKind::NotFound {
            Error::new(MANIFEST, format!("unknown command {name:?} (no {exe} on PATH)"))
        } else {
            Error::new(error::IO, format!("{exe}: {e}"))
        }
    })?;
    std::process::exit(status.code().unwrap_or(1));
}

fn main() {
    // clap exits 2 on usage errors, which here means authentication.
    let cli = Cli::try_parse().unwrap_or_else(|e| {
        let _ = e.print();
        std::process::exit(if e.use_stderr() { MANIFEST.into() } else { 0 });
    });
    if let Err(e) = run(cli) {
        eprintln!("error: {e}");
        std::process::exit(e.code.into());
    }
}
