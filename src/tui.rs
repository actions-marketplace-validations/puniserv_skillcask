//! `skillcask ui` (D41): a terminal UI that holds no package logic. Every step runs this binary
//! as a child and reads its `--json` documents or shows its output.

use std::collections::HashMap;
use std::io::{IsTerminal, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use ratatui::crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use ratatui::layout::{Constraint, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::widgets::{Block, List, ListItem, ListState, Paragraph, Wrap};
use ratatui::{DefaultTerminal, Frame};
use serde_json::Value;

use crate::error::{Error, IO, MANIFEST, Result};

const HELP: [&str; 14] = [
    "↑↓/jk move",
    "pgup/pgdn scroll",
    "tab info/audit/output",
    "g project/global",
    "i install",
    "a add",
    "u diff, then update",
    "x remove",
    "o doctor",
    "f doctor --fix",
    "/ search",
    "p find projects",
    "r refresh",
    "q quit",
];
const SKILL_MD_MAX: u64 = 256 * 1024;

pub fn run(global: bool) -> Result<()> {
    if !std::io::stdout().is_terminal() {
        return Err(
            Error::new(MANIFEST, "skillcask ui needs a terminal").hint("in scripts use status, outdated, info or audit with --json")
        );
    }
    let project = crate::project::find_root().ok();
    let global = global || project.is_none();
    let mut app = App::new(std::env::current_exe()?, std::env::current_dir()?, project, global, crate::scope::home());
    // try_init also installs a panic hook that restores the terminal.
    let mut term = ratatui::try_init().map_err(|e| {
        ratatui::restore();
        Error::new(IO, format!("terminal: {e}"))
    })?;
    let r = event_loop(&mut term, &mut app);
    ratatui::restore();
    r.map_err(|e| Error::new(IO, format!("terminal: {e}")))
}

fn event_loop(term: &mut DefaultTerminal, app: &mut App) -> std::io::Result<()> {
    let mut job = Some(Job::Refresh);
    while !app.quit {
        match job.take().or_else(|| app.missing_detail()) {
            Some(j) => {
                app.message = "working…".into();
                term.draw(|f| draw(f, app))?;
                app.message.clear();
                perform(app, j);
            }
            None => {
                term.draw(|f| draw(f, app))?;
                // Windows reports key releases too.
                if let Event::Key(k) = event::read()?
                    && k.kind == KeyEventKind::Press
                {
                    job = app.key(k);
                }
            }
        }
    }
    Ok(())
}

#[derive(Debug, Clone, PartialEq)]
struct Row {
    package: Option<String>,
    version: Option<String>,
    skill: Option<String>,
    state: String,
    ok: bool,
    adopt: Option<String>,
    update: Option<String>,
}

#[derive(Debug, PartialEq)]
enum Job {
    Refresh,
    Detail(String),
    /// A command that changes something: show its output, then refresh.
    Run(Vec<String>),
    /// Show `diff <pkg>`, then ask before `update <pkg>`.
    Diff(String),
    Doctor,
    Projects(String),
    Search(String),
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Then {
    Add,
    Adopt,
    Projects,
    Search,
    Switch,
    /// A picked search result, to edit before `add`.
    Prefill,
}

#[derive(Debug, PartialEq)]
enum Mode {
    List,
    Input {
        prompt: &'static str,
        text: String,
        then: Then,
    },
    Confirm {
        question: String,
        args: Vec<String>,
    },
    /// `items` are (value, label).
    Pick {
        title: String,
        items: Vec<(String, String)>,
        sel: usize,
        then: Then,
    },
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum View {
    Info,
    Audit,
    Output,
}

struct Out {
    code: Option<i32>,
    stdout: String,
    stderr: String,
}

struct App {
    exe: PathBuf,
    cwd: PathBuf,
    project: Option<PathBuf>,
    global: bool,
    home: Option<PathBuf>,
    rows: Vec<Row>,
    sel: usize,
    audit: Vec<Value>,
    details: HashMap<String, Vec<String>>,
    view: View,
    output: Vec<String>,
    scroll: u16,
    mode: Mode,
    message: String,
    quit: bool,
}

impl App {
    fn new(exe: PathBuf, cwd: PathBuf, project: Option<PathBuf>, global: bool, home: Option<PathBuf>) -> App {
        App {
            exe,
            cwd,
            project,
            global,
            home,
            rows: Vec::new(),
            sel: 0,
            audit: Vec::new(),
            details: HashMap::new(),
            view: View::Info,
            output: Vec::new(),
            scroll: 0,
            mode: Mode::List,
            message: String::new(),
            quit: false,
        }
    }

    /// Base of the relative paths in the JSON documents.
    fn root(&self) -> Option<&Path> {
        if self.global { self.home.as_deref() } else { self.project.as_deref() }
    }

    fn no_manifest(&self) -> bool {
        !self.global && self.project.as_ref().is_none_or(|p| !p.join(crate::manifest::FILE).is_file())
    }

    fn selected(&self) -> Option<&Row> {
        self.rows.get(self.sel)
    }

    fn missing_detail(&self) -> Option<Job> {
        let r = self.selected().filter(|r| r.state != "not managed")?;
        let skill = r.skill.as_ref()?;
        (!self.details.contains_key(skill)).then(|| Job::Detail(skill.clone()))
    }

    fn cli(&self, args: &[String]) -> Out {
        let dir = if self.global { &self.cwd } else { self.project.as_ref().unwrap_or(&self.cwd) };
        spawn(&self.exe, dir, self.global, args)
    }

    fn key(&mut self, k: KeyEvent) -> Option<Job> {
        if k.modifiers.contains(KeyModifiers::CONTROL) && k.code == KeyCode::Char('c') {
            self.quit = true;
            return None;
        }
        match std::mem::replace(&mut self.mode, Mode::List) {
            Mode::List => self.list_key(k.code),
            Mode::Input { prompt, mut text, then } => match k.code {
                KeyCode::Esc => None,
                KeyCode::Enter if !text.trim().is_empty() => self.submit(then, text.trim().to_string()),
                code => {
                    match code {
                        KeyCode::Backspace => {
                            text.pop();
                        }
                        KeyCode::Char(c) => text.push(c),
                        _ => {}
                    }
                    self.mode = Mode::Input { prompt, text, then };
                    None
                }
            },
            Mode::Confirm { args, .. } if k.code == KeyCode::Char('y') => Some(Job::Run(args)),
            Mode::Confirm { .. } => {
                self.message = "cancelled".into();
                None
            }
            Mode::Pick { title, items, mut sel, then } => match k.code {
                KeyCode::Esc => None,
                KeyCode::Enter => match items.get(sel) {
                    Some((v, _)) => self.submit(then, v.clone()),
                    None => None,
                },
                code => {
                    match code {
                        KeyCode::Down | KeyCode::Char('j') => sel = (sel + 1).min(items.len().saturating_sub(1)),
                        KeyCode::Up | KeyCode::Char('k') => sel = sel.saturating_sub(1),
                        _ => {}
                    }
                    self.mode = Mode::Pick { title, items, sel, then };
                    None
                }
            },
        }
    }

    fn list_key(&mut self, code: KeyCode) -> Option<Job> {
        let package = self.selected().and_then(|r| r.package.clone());
        match code {
            KeyCode::Char('q') => self.quit = true,
            KeyCode::Down | KeyCode::Char('j') => {
                self.sel = (self.sel + 1).min(self.rows.len().saturating_sub(1));
                self.scroll = 0;
            }
            KeyCode::Up | KeyCode::Char('k') => {
                self.sel = self.sel.saturating_sub(1);
                self.scroll = 0;
            }
            KeyCode::PageDown => self.scroll = self.scroll.saturating_add(10),
            KeyCode::PageUp => self.scroll = self.scroll.saturating_sub(10),
            KeyCode::Tab => {
                self.view = match self.view {
                    View::Info => View::Audit,
                    View::Audit => View::Output,
                    View::Output => View::Info,
                };
                self.scroll = 0;
            }
            KeyCode::Char('g') => {
                self.global = !self.global;
                self.sel = 0;
                return Some(Job::Refresh);
            }
            KeyCode::Char('r') => return Some(Job::Refresh),
            KeyCode::Char('i') if self.no_manifest() && self.project.is_some() => return Some(Job::Run(args(&["init"]))),
            KeyCode::Char('i') => return Some(Job::Run(args(&["install"]))),
            KeyCode::Char('a') => {
                self.mode = match self.selected().filter(|r| r.state == "not managed").map(|r| r.adopt.clone()) {
                    Some(Some(src)) => Mode::Input { prompt: "adopt with add --adopt", text: src, then: Then::Adopt },
                    // A plain add would only fail on the copy that stands at the name.
                    Some(None) => Mode::Input { prompt: "adopt: no source recorded, type it", text: String::new(), then: Then::Adopt },
                    None => Mode::Input { prompt: "add source", text: String::new(), then: Then::Add },
                }
            }
            KeyCode::Char('u') | KeyCode::Char('x') if package.is_none() => self.message = "not a package".into(),
            KeyCode::Char('u') => return package.map(Job::Diff),
            KeyCode::Char('x') => {
                let p = package?;
                self.mode = Mode::Confirm { question: format!("remove {p}? (y/n)"), args: args(&["remove", "--", &p]) };
            }
            KeyCode::Char('o') => return Some(Job::Doctor),
            KeyCode::Char('f') => return Some(Job::Run(args(&["doctor", "--fix"]))),
            KeyCode::Char('/') => self.mode = Mode::Input { prompt: "search", text: String::new(), then: Then::Search },
            KeyCode::Char('p') => {
                let home = self.home.as_ref().map_or(".".into(), |h| h.display().to_string());
                self.mode = Mode::Input { prompt: "find projects under", text: home, then: Then::Projects };
            }
            _ => {}
        }
        None
    }

    fn submit(&mut self, then: Then, v: String) -> Option<Job> {
        match then {
            Then::Add => Some(Job::Run(args(&["add", "--", &v]))),
            Then::Adopt => Some(Job::Run(args(&["add", "--adopt", "--", &v]))),
            Then::Projects => Some(Job::Projects(v)),
            Then::Search => Some(Job::Search(v)),
            Then::Prefill => {
                self.mode = Mode::Input { prompt: "add source", text: v, then: Then::Add };
                None
            }
            Then::Switch => {
                self.project = Some(PathBuf::from(v));
                self.global = false;
                self.sel = 0;
                Some(Job::Refresh)
            }
        }
    }

    fn show(&mut self, args: &[String], out: &Out) {
        let code = out.code.map_or("killed".into(), |c| format!("exit {c}"));
        self.output = vec![format!("$ skillcask {}{} ({code})", if self.global { "--global " } else { "" }, args.join(" "))];
        self.output.extend(clean(&out.stdout));
        self.output.extend(clean(&out.stderr));
        self.view = View::Output;
        self.scroll = 0;
    }

    fn refreshed(&mut self, status: &Out, outdated: &Out, audit: &Out) {
        self.details.clear();
        self.audit = json(audit).ok().and_then(|a| a["skills"].as_array().cloned()).unwrap_or_default();
        match json(status) {
            Ok(st) => {
                let od = json(outdated).unwrap_or_else(|e| {
                    self.message = format!("outdated: {e}");
                    Value::Null
                });
                self.rows = rows(&st, &od);
            }
            Err(e) => {
                self.rows.clear();
                self.message = e;
            }
        }
        self.sel = self.sel.min(self.rows.len().saturating_sub(1));
    }

    fn detail_lines(&self) -> Vec<String> {
        let Some(r) = self.selected() else { return Vec::new() };
        let Some(skill) = &r.skill else {
            return [("package", &r.package), ("version", &r.version), ("state", &Some(r.state.clone()))]
                .iter()
                .filter_map(|(k, v)| v.as_ref().map(|v| format!("{k}: {v}")))
                .collect();
        };
        match self.view {
            // `info` knows only installed packages and project skills.
            View::Info if r.state == "not managed" => vec![
                "not managed by skillcask".into(),
                match &r.adopt {
                    Some(src) => format!("npx skills recorded the source {src}"),
                    None => "no source recorded".into(),
                },
                "press a to adopt: the copy moves to ~/.config/skillcask/adopted/ and the package's skill is installed".into(),
            ],
            View::Info => self.details.get(skill).cloned().unwrap_or_default(),
            View::Audit => audit_lines(&self.audit, skill),
            View::Output => self.output.clone(),
        }
    }
}

fn args(a: &[&str]) -> Vec<String> {
    a.iter().map(|s| s.to_string()).collect()
}

/// The child gets no stdin, so it never prompts; `--` keeps a typed source from being read as a flag.
fn spawn(exe: &Path, dir: &Path, global: bool, args: &[String]) -> Out {
    let mut c = Command::new(exe);
    if global {
        c.arg("--global");
    }
    c.args(args).current_dir(dir).stdin(Stdio::null()).env("NO_COLOR", "1").env("SKILLCASK_AGENT", "0");
    match c.output() {
        Ok(o) => Out {
            code: o.status.code(),
            stdout: String::from_utf8_lossy(&o.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&o.stderr).into_owned(),
        },
        Err(e) => Out { code: None, stdout: String::new(), stderr: format!("{}: {e}", exe.display()) },
    }
}

fn perform(app: &mut App, job: Job) {
    match job {
        Job::Refresh => {
            if app.no_manifest() {
                app.rows.clear();
                app.details.clear();
                app.message = match &app.project {
                    Some(p) => format!("no skills.toml in {}: press i to run init, g for global, p to pick a project", p.display()),
                    None => "no project here: press g for global or p to pick a project".into(),
                };
                return;
            }
            let st = app.cli(&args(&["status", "--json"]));
            let au = app.cli(&args(&["audit", "--json"]));
            let od = app.cli(&args(&["outdated", "--json"]));
            app.refreshed(&st, &od, &au);
        }
        Job::Detail(skill) => {
            let out = app.cli(&args(&["info", "--json", "--", &skill]));
            let lines = detail(&out, app.root());
            app.details.insert(skill, lines);
        }
        Job::Run(a) => {
            let out = app.cli(&a);
            app.show(&a, &out);
            perform(app, Job::Refresh);
        }
        Job::Diff(p) => {
            let a = args(&["diff", "--", &p]);
            let out = app.cli(&a);
            app.show(&a, &out);
            if out.code == Some(0) {
                app.mode = Mode::Confirm { question: format!("update {p}? (y/n)"), args: args(&["update", "--", &p]) };
            }
        }
        Job::Doctor => {
            let a = args(&["doctor", "--json"]);
            let out = app.cli(&a);
            let doc = json(&out).map_or_else(|e| vec![e], |d| value_lines(&d));
            app.show(&a, &Out { stdout: String::new(), ..out });
            app.output.extend(doc);
        }
        Job::Projects(dir) => {
            let out = spawn(&app.exe, &app.cwd, false, &args(&["projects", "--json", "--", &dir]));
            match json(&out) {
                Ok(d) => {
                    let items = list(&d["projects"], |p| Some((p["path"].as_str()?.to_string(), clean(p["path"].as_str()?).join(" "))));
                    app.mode = Mode::Pick { title: format!("projects under {dir}"), items, sel: 0, then: Then::Switch };
                }
                Err(e) => app.message = e,
            }
        }
        Job::Search(q) => {
            let out = app.cli(&args(&["search", "--json", "--", &q]));
            match json(&out) {
                Ok(d) => {
                    let items = list(&d["results"], |r| {
                        let name = r["name"].as_str()?;
                        Some((name.to_string(), format!("{name}  {}", r["description"].as_str().unwrap_or(""))))
                    });
                    app.mode = Mode::Pick { title: format!("search {q}"), items, sel: 0, then: Then::Prefill };
                }
                Err(e) => app.message = e,
            }
        }
    }
}

fn list(v: &Value, f: impl Fn(&Value) -> Option<(String, String)>) -> Vec<(String, String)> {
    v.as_array().into_iter().flatten().filter_map(f).collect()
}

/// A command's JSON document, or its error as one line. `status` and `audit` print the
/// document and exit 1 when they find a problem.
fn json(out: &Out) -> std::result::Result<Value, String> {
    serde_json::from_str(&out.stdout).map_err(|_| {
        let err = clean(&out.stderr).into_iter().find(|l| !l.trim().is_empty());
        err.unwrap_or_else(|| format!("exit {}", out.code.unwrap_or(-1)))
    })
}

/// `status --json` entries with the version `update` would lock from `outdated --json`.
fn rows(status: &Value, outdated: &Value) -> Vec<Row> {
    let s = |v: &Value| v.as_str().map(String::from);
    let updates: HashMap<&str, &str> = outdated["packages"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|p| p["within"] != p["locked"])
        .filter_map(|p| Some((p["package"].as_str()?, p["within"].as_str()?)))
        .collect();
    status["entries"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|e| {
            // A dependency's label is `name (via requirer, …)`.
            let package = e["package"].as_str().and_then(|p| p.split(' ').next()).map(String::from);
            Row {
                update: package.as_deref().and_then(|p| updates.get(p)).map(|u| u.to_string()),
                package,
                version: s(&e["version"]),
                skill: s(&e["skill"]),
                state: s(&e["state"]).unwrap_or_default(),
                ok: e["ok"].as_bool().unwrap_or(false),
                adopt: s(&e["adopt"]),
            }
        })
        .collect()
}

/// Text from a child or a skill with control and invisible characters shown as `<U+XXXX>`,
/// so a skill cannot send escape sequences to the terminal.
fn clean(s: &str) -> Vec<String> {
    s.lines().map(|l| crate::skill::shown(l).replace('\t', "    ")).collect()
}

/// A JSON document as `key: value` lines, arrays one item per line.
fn value_lines(v: &Value) -> Vec<String> {
    let one = |v: &Value| v.as_str().map_or_else(|| v.to_string(), String::from);
    let mut out = Vec::new();
    for (k, v) in v.as_object().into_iter().flatten() {
        match v {
            Value::Null => {}
            Value::Array(a) if a.is_empty() => {}
            Value::Array(a) => {
                out.push(format!("{k}:"));
                out.extend(a.iter().map(|x| format!("  {}", one(x))));
            }
            v => out.push(format!("{k}: {}", one(v))),
        }
    }
    out.iter().flat_map(|l| clean(l)).collect()
}

/// `info --json` and, read-only, the SKILL.md at its `path`.
fn detail(out: &Out, root: Option<&Path>) -> Vec<String> {
    let info = match json(out) {
        Ok(v) => v,
        Err(e) => return vec![e],
    };
    let mut lines = value_lines(&info);
    if let (Some(root), Some(p)) = (root, info["path"].as_str()) {
        lines.push(String::new());
        let mut text = Vec::new();
        match std::fs::File::open(root.join(p).join("SKILL.md")).and_then(|f| f.take(SKILL_MD_MAX).read_to_end(&mut text)) {
            Ok(_) => lines.extend(clean(&String::from_utf8_lossy(&text))),
            Err(e) => lines.push(format!("SKILL.md: {e}")),
        }
    }
    lines
}

fn audit_lines(audit: &[Value], skill: &str) -> Vec<String> {
    let Some(a) = audit.iter().find(|a| a["skill"] == skill) else { return vec!["not in audit".into()] };
    let findings = a["findings"].as_array().map_or(&[][..], |f| f.as_slice());
    let mut out = vec![if findings.is_empty() { "no findings".to_string() } else { "findings:".to_string() }];
    for f in findings {
        let at = f["line"].as_u64().map_or(String::new(), |l| format!(":{l}"));
        out.push(format!(
            "  {} {}{at} {}",
            f["rule"].as_str().unwrap_or(""),
            f["path"].as_str().unwrap_or(""),
            f["message"].as_str().unwrap_or("")
        ));
    }
    let reach: serde_json::Map<String, Value> =
        ["commands", "network", "paths", "env", "scripts"].iter().map(|k| (k.to_string(), a[*k].clone())).collect();
    out.extend(value_lines(&Value::Object(reach)));
    out.iter().flat_map(|l| clean(l)).collect()
}

/// The keys of the current mode.
fn keys(app: &App) -> Vec<&'static str> {
    match &app.mode {
        Mode::Input { .. } => vec!["enter submit", "esc cancel", "backspace delete"],
        Mode::Confirm { .. } => vec!["y yes", "any other key no"],
        Mode::Pick { .. } => vec!["↑↓/jk move", "enter choose", "esc cancel"],
        Mode::List if app.selected().is_some_and(|r| r.state == "not managed") => {
            HELP.iter().map(|k| if *k == "a add" { "a adopt" } else { k }).collect()
        }
        Mode::List => HELP.to_vec(),
    }
}

/// Packs the keys into lines of at most `width` columns, never splitting one key.
fn legend(keys: &[&str], width: u16) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for k in keys {
        match lines.last_mut() {
            Some(l) if l.chars().count() + 2 + k.chars().count() <= width as usize => {
                l.push_str("  ");
                l.push_str(k);
            }
            _ => lines.push(k.to_string()),
        }
    }
    lines
}

fn draw(f: &mut Frame, app: &App) {
    let legend = legend(&keys(app), f.area().width);
    let [head, body, msg, help] =
        Layout::vertical([Constraint::Length(1), Constraint::Fill(1), Constraint::Length(1), Constraint::Length(legend.len() as u16)])
            .areas(f.area());
    let [left, right] = Layout::horizontal([Constraint::Percentage(45), Constraint::Fill(1)]).areas(body);

    let scope = match (&app.project, app.global) {
        (_, true) => "global".to_string(),
        (Some(p), false) => format!("project {}", p.display()),
        (None, false) => "project (none)".to_string(),
    };
    f.render_widget(
        Paragraph::new(clean(&format!("skillcask ui  {scope}")).join(" ")).style(Style::new().add_modifier(Modifier::BOLD)),
        head,
    );

    let highlight = Style::new().add_modifier(Modifier::REVERSED);
    if let Mode::Pick { title, items, sel, .. } = &app.mode {
        let items: Vec<ListItem> = items.iter().map(|(_, l)| ListItem::new(clean(l).join(" "))).collect();
        let list = List::new(items).block(Block::bordered().title(clean(title).join(" "))).highlight_style(highlight);
        f.render_stateful_widget(list, left, &mut ListState::default().with_selected(Some(*sel)));
    } else {
        let items: Vec<ListItem> = app
            .rows
            .iter()
            .map(|r| {
                let name = r.skill.as_ref().or(r.package.as_ref()).map_or("-", |s| s.as_str());
                let up = r.update.as_ref().map_or(String::new(), |u| format!("  ↑ {u}"));
                let line = format!("{name:<24} {:<10} {}{up}", r.version.as_deref().unwrap_or("-"), r.state);
                let color = if !r.ok {
                    Color::Red
                } else if r.update.is_some() {
                    Color::Yellow
                } else {
                    Color::Reset
                };
                ListItem::new(clean(&line).join(" ")).style(Style::new().fg(color))
            })
            .collect();
        let list = List::new(items).block(Block::bordered().title("skills")).highlight_style(highlight);
        f.render_stateful_widget(list, left, &mut ListState::default().with_selected(Some(app.sel)));
    }

    let title = match app.view {
        View::Info => "info",
        View::Audit => "audit",
        View::Output => "output",
    };
    let lines = if app.view == View::Output { app.output.clone() } else { app.detail_lines() };
    f.render_widget(
        Paragraph::new(lines.join("\n")).block(Block::bordered().title(title)).wrap(Wrap { trim: false }).scroll((app.scroll, 0)),
        right,
    );

    let line = match &app.mode {
        Mode::Input { prompt, text, .. } => format!("{prompt}: {text}_"),
        Mode::Confirm { question, .. } => question.clone(),
        Mode::Pick { .. } | Mode::List => app.message.clone(),
    };
    f.render_widget(Paragraph::new(clean(&line).join(" ")), msg);
    f.render_widget(Paragraph::new(legend.join("\n")), help);
}

#[cfg(test)]
mod tests {
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;
    use serde_json::json;

    use super::*;

    fn app(rows: Vec<Row>, global: bool) -> App {
        let mut a = App::new("skillcask".into(), ".".into(), Some("/p".into()), global, Some("/h".into()));
        a.rows = rows;
        a
    }

    fn out(stdout: &str) -> Out {
        Out { code: Some(0), stdout: stdout.into(), stderr: String::new() }
    }

    fn press(a: &mut App, c: KeyCode) -> Option<Job> {
        a.key(KeyEvent::new(c, KeyModifiers::NONE))
    }

    fn typed(a: &mut App, s: &str) {
        for c in s.chars() {
            press(a, KeyCode::Char(c));
        }
    }

    fn sample() -> Vec<Row> {
        let st = json!({ "ok": false, "entries": [
            { "package": "acme/one", "version": "1.0.0", "skill": "one", "state": "ok", "ok": true, "adopt": null },
            { "package": "acme/dep (via acme/one)", "version": "2.0.0", "skill": "dep", "state": "modified", "ok": false, "adopt": null },
            { "package": null, "version": null, "skill": "mine", "state": "not managed", "ok": true, "adopt": "github:o/r/mine" },
        ]});
        let od = json!({ "packages": [
            { "package": "acme/one", "locked": "1.0.0", "within": "1.1.0", "latest": "2.0.0", "note": null },
            { "package": "acme/dep", "locked": "2.0.0", "within": "2.0.0", "latest": "2.0.0", "note": null },
        ], "behind": [] });
        rows(&st, &od)
    }

    #[test]
    fn rows_join_status_and_outdated() {
        let r = sample();
        assert_eq!(r.len(), 3);
        assert_eq!((r[0].update.as_deref(), r[0].ok), (Some("1.1.0"), true));
        assert_eq!((r[1].package.as_deref(), r[1].update.as_deref(), r[1].ok), (Some("acme/dep"), None, false));
        assert_eq!((r[2].package.as_deref(), r[2].adopt.as_deref()), (None, Some("github:o/r/mine")));
        assert!(rows(&json!({ "entries": [] }), &Value::Null).is_empty());
    }

    #[test]
    fn update_shows_the_diff_first_and_remove_asks() {
        let mut a = app(sample(), false);
        assert_eq!(press(&mut a, KeyCode::Char('u')), Some(Job::Diff("acme/one".into())));
        a.mode = Mode::Confirm { question: "update acme/one? (y/n)".into(), args: args(&["update", "--", "acme/one"]) };
        assert_eq!(press(&mut a, KeyCode::Char('n')), None);
        assert_eq!((&a.mode, a.message.as_str()), (&Mode::List, "cancelled"));

        press(&mut a, KeyCode::Down);
        assert_eq!(press(&mut a, KeyCode::Char('x')), None);
        assert_eq!(press(&mut a, KeyCode::Char('y')), Some(Job::Run(args(&["remove", "--", "acme/dep"]))));

        press(&mut a, KeyCode::Down);
        assert_eq!(press(&mut a, KeyCode::Char('u')), None);
        assert_eq!(a.message, "not a package");
    }

    #[test]
    fn the_legend_follows_the_mode_and_wraps_without_splitting_a_key() {
        let mut a = app(sample(), true);
        assert!(keys(&a).contains(&"a add"));
        a.sel = 2;
        assert!(keys(&a).contains(&"a adopt"));
        a.mode = Mode::Confirm { question: String::new(), args: Vec::new() };
        assert_eq!(keys(&a), ["y yes", "any other key no"]);
        assert_eq!(legend(&["ab", "cd", "efg"], 6), ["ab  cd", "efg"]);
        let lines = legend(&HELP, 40);
        assert!(lines.len() > 1 && lines.iter().all(|l| l.chars().count() <= 40));
        assert_eq!(lines.join("  "), HELP.join("  "));
    }

    #[test]
    fn an_unmanaged_skill_explains_adopt_instead_of_running_info() {
        // Regression: info failed with "no installed skill" for every not managed row.
        let mut a = app(sample(), true);
        a.sel = 2;
        assert_eq!(a.missing_detail(), None);
        let lines = a.detail_lines();
        assert!(lines.iter().any(|l| l.contains("github:o/r/mine")) && lines.iter().any(|l| l.starts_with("press a")), "{lines:?}");
    }

    #[test]
    fn add_prompts_and_adopt_is_prefilled_for_unmanaged_skills() {
        let mut a = app(sample(), true);
        press(&mut a, KeyCode::Char('a'));
        typed(&mut a, "acme/twx");
        press(&mut a, KeyCode::Backspace);
        typed(&mut a, "o");
        assert_eq!(press(&mut a, KeyCode::Enter), Some(Job::Run(args(&["add", "--", "acme/two"]))));

        a.sel = 2;
        press(&mut a, KeyCode::Char('a'));
        assert!(matches!(&a.mode, Mode::Input { text, then: Then::Adopt, .. } if text == "github:o/r/mine"));
        assert_eq!(press(&mut a, KeyCode::Enter), Some(Job::Run(args(&["add", "--adopt", "--", "github:o/r/mine"]))));

        press(&mut a, KeyCode::Char('a'));
        assert_eq!(press(&mut a, KeyCode::Esc), None);

        // Regression: an unmanaged skill without a recorded source got a plain add prompt.
        a.rows[2].adopt = None;
        press(&mut a, KeyCode::Char('a'));
        assert!(matches!(&a.mode, Mode::Input { text, then: Then::Adopt, .. } if text.is_empty()));
        typed(&mut a, "github:o/r/mine");
        assert_eq!(press(&mut a, KeyCode::Enter), Some(Job::Run(args(&["add", "--adopt", "--", "github:o/r/mine"]))));
        assert_eq!(a.mode, Mode::List);
    }

    #[test]
    fn scope_toggles_and_a_picked_project_becomes_the_scope() {
        let mut a = app(sample(), false);
        assert_eq!(press(&mut a, KeyCode::Char('g')), Some(Job::Refresh));
        assert!(a.global);
        assert_eq!(a.root(), Some(Path::new("/h")));

        press(&mut a, KeyCode::Char('p'));
        assert!(matches!(&a.mode, Mode::Input { text, .. } if text == "/h"));
        assert_eq!(press(&mut a, KeyCode::Enter), Some(Job::Projects("/h".into())));
        a.mode = Mode::Pick {
            title: "t".into(),
            items: vec![("/a".into(), "/a".into()), ("/b".into(), "/b".into())],
            sel: 0,
            then: Then::Switch,
        };
        press(&mut a, KeyCode::Down);
        assert_eq!(press(&mut a, KeyCode::Enter), Some(Job::Refresh));
        assert_eq!((a.global, a.project.as_deref()), (false, Some(Path::new("/b"))));
    }

    #[test]
    fn i_runs_init_without_a_manifest() {
        let tmp = tempfile::tempdir().unwrap();
        let mut a = app(Vec::new(), false);
        a.project = Some(tmp.path().to_path_buf());
        assert_eq!(press(&mut a, KeyCode::Char('i')), Some(Job::Run(args(&["init"]))));
        std::fs::write(tmp.path().join("skills.toml"), "").unwrap();
        assert_eq!(press(&mut a, KeyCode::Char('i')), Some(Job::Run(args(&["install"]))));
        assert_eq!(press(&mut a, KeyCode::Char('q')), None);
        assert!(a.quit);
    }

    #[test]
    fn skill_text_cannot_drive_the_terminal() {
        assert_eq!(clean("a\x1b]52;c;eA==\x07b\r\n\u{200b}c\td"), ["a<U+001B>]52;c;eA==<U+0007>b", "<U+200B>c    d"]);

        let tmp = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(tmp.path().join(".agents/skills/one")).unwrap();
        std::fs::write(tmp.path().join(".agents/skills/one/SKILL.md"), "# One\n\x1b[2Jboom").unwrap();
        let info = out(r#"{"skill":"one","kind":"package","package":"acme/one","path":".agents/skills/one","why":["acme/one: x"]}"#);
        let lines = detail(&info, Some(tmp.path()));
        assert_eq!(
            lines,
            [
                "kind: package",
                "package: acme/one",
                "path: .agents/skills/one",
                "skill: one",
                "why:",
                "  acme/one: x",
                "",
                "# One",
                "<U+001B>[2Jboom"
            ]
        );
        let err = Out { code: Some(1), stdout: String::new(), stderr: "error: no installed skill \"x\"\n".into() };
        assert_eq!(detail(&err, None), ["error: no installed skill \"x\""]);
    }

    #[test]
    fn audit_lists_findings_and_reach_of_the_skill() {
        let audit = vec![
            json!({ "skill": "one", "findings": [{ "rule": "risky-pattern", "path": ".agents/skills/one/SKILL.md", "line": 3, "message": "curl piped into sh" }],
            "commands": ["curl"], "network": [], "paths": [], "env": ["HOME"], "scripts": [] }),
        ];
        assert_eq!(
            audit_lines(&audit, "one"),
            ["findings:", "  risky-pattern .agents/skills/one/SKILL.md:3 curl piped into sh", "commands:", "  curl", "env:", "  HOME"]
        );
        assert_eq!(audit_lines(&audit, "two"), ["not in audit"]);
    }

    #[test]
    fn draws_rows_detail_and_help() {
        let mut a = app(sample(), false);
        a.details.insert("one".into(), vec!["skill: one".into()]);
        a.message = "bad\x1b[31m".into();
        let mut t = Terminal::new(TestBackend::new(160, 12)).unwrap();
        t.draw(|f| draw(f, &a)).unwrap();
        let screen: String = t.backend().buffer().content().iter().map(|c| c.symbol()).collect();
        assert!(screen.contains("project /p"), "{screen}");
        assert!(screen.contains("one                      1.0.0      ok  ↑ 1.1.0"), "{screen}");
        assert!(screen.contains("skill: one"), "{screen}");
        assert!(screen.contains("bad<U+001B>[31m"), "{screen}");
        assert!(screen.contains("q quit"), "{screen}");
    }
}
