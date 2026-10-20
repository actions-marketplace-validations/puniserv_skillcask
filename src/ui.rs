//! Output for people (colour in a terminal) or for agents (terse, plain) (D19).

use std::fmt::Display;
use std::io::IsTerminal;
use std::sync::OnceLock;

#[derive(Clone, Copy, Debug, PartialEq)]
struct Style {
    agent: bool,
    color_out: bool,
    color_err: bool,
}

static STYLE: OnceLock<Style> = OnceLock::new();

/// Decides the mode once; `--agent` is only known after parsing the command line.
pub fn init(agent_flag: bool) {
    let _ = STYLE.set(detect(agent_flag, |k| std::env::var(k).ok(), std::io::stdout().is_terminal(), std::io::stderr().is_terminal()));
}

fn style() -> Style {
    *STYLE.get_or_init(|| detect(false, |k| std::env::var(k).ok(), std::io::stdout().is_terminal(), std::io::stderr().is_terminal()))
}

fn detect(flag: bool, var: impl Fn(&str) -> Option<String>, out_tty: bool, err_tty: bool) -> Style {
    let set = |k: &str| var(k).is_some_and(|v| !v.is_empty());
    let agent = flag
        || match var("SKILLCASK_AGENT").as_deref() {
            Some("1" | "true") => true,
            Some("0" | "false") => false,
            _ => set("AI_AGENT") || var("CLAUDECODE").as_deref() == Some("1"),
        };
    // The legacy Windows console prints escape codes instead of interpreting them.
    let ansi = !cfg!(windows) || set("WT_SESSION");
    let forced = var("CLICOLOR_FORCE").is_some_and(|v| !v.is_empty() && v != "0");
    let color = |tty: bool| !agent && !set("NO_COLOR") && (forced || tty && ansi);
    Style { agent, color_out: color(out_tty), color_err: color(err_tty) }
}

/// Terse, uncoloured output for a coding agent.
pub fn agent() -> bool {
    style().agent
}

#[derive(Clone, Copy)]
pub enum Color {
    Red,
    Green,
    Yellow,
    Cyan,
    Dim,
}

fn paint(c: Color, s: impl Display, on: bool) -> String {
    if !on {
        return s.to_string();
    }
    let code = match c {
        Color::Red => "1;31",
        Color::Green => "1;32",
        Color::Yellow => "1;33",
        Color::Cyan => "1;36",
        Color::Dim => "2",
    };
    format!("\x1b[{code}m{s}\x1b[0m")
}

/// `s` coloured for stdout.
pub fn out(c: Color, s: impl Display) -> String {
    paint(c, s, style().color_out)
}

fn err(c: Color, s: impl Display) -> String {
    paint(c, s, style().color_err)
}

/// Messages quote names, versions and URLs from registries; only our own line breaks survive.
fn lines(msg: impl Display) -> String {
    msg.to_string().chars().map(|c| if c.is_control() && c != '\n' { ' ' } else { c }).collect()
}

pub fn warn(msg: impl Display) {
    eprintln!("{}: {}", err(Color::Yellow, "warning"), lines(msg));
}

pub fn note(msg: impl Display) {
    eprintln!("{}: {}", err(Color::Cyan, "note"), lines(msg));
}

pub fn error(msg: impl Display, hint: Option<&str>) {
    eprintln!("{}: {}", err(Color::Red, "error"), lines(msg));
    if let Some(h) = hint {
        eprintln!("  {}: {}", err(Color::Cyan, "hint"), lines(h));
    }
}

/// Text from a registry with control characters replaced: a description could otherwise carry
/// terminal escape sequences (window title, clipboard writes through OSC 52).
pub fn printable(s: &str) -> String {
    s.chars().map(|c| if c.is_control() { ' ' } else { c }).collect()
}

/// A line on stdout led by a green verb: `installed x (vendor/x 1.0.0)`.
pub fn done(verb: &str, rest: impl Display) {
    println!("{} {rest}", out(Color::Green, verb));
}

/// Columns aligned for a person, tab-separated for an agent; `color` colours a cell after
/// padding, so escape codes do not break the alignment.
pub fn table<const N: usize>(rows: &[[String; N]], color: impl Fn(usize, &str) -> Option<Color>) {
    if agent() {
        for r in rows {
            println!("{}", r.join("\t"));
        }
        return;
    }
    let mut w = [0; N];
    for r in rows {
        for (i, c) in r.iter().enumerate() {
            w[i] = w[i].max(c.chars().count());
        }
    }
    for (n, r) in rows.iter().enumerate() {
        let cells: Vec<String> = r
            .iter()
            .enumerate()
            .map(|(i, c)| {
                let padded = format!("{c:w$}", w = w[i]);
                match (n, color(i, c)) {
                    (0, _) => out(Color::Dim, padded),
                    (_, Some(k)) => out(k, padded),
                    _ => padded,
                }
            })
            .collect();
        println!("{}", cells.join("  ").trim_end());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env(pairs: &'static [(&'static str, &'static str)]) -> impl Fn(&str) -> Option<String> {
        move |k| pairs.iter().find(|(n, _)| *n == k).map(|(_, v)| v.to_string())
    }

    #[test]
    fn detects_agents() {
        assert!(!detect(false, env(&[]), true, true).agent);
        assert!(detect(true, env(&[]), true, true).agent);
        assert!(detect(false, env(&[("AI_AGENT", "claude-code_2-1-280_agent")]), true, true).agent);
        assert!(detect(false, env(&[("CLAUDECODE", "1")]), true, true).agent);
        assert!(!detect(false, env(&[("CLAUDECODE", "0")]), true, true).agent);
        assert!(!detect(false, env(&[("AI_AGENT", "x"), ("SKILLCASK_AGENT", "0")]), true, true).agent);
        assert!(detect(false, env(&[("SKILLCASK_AGENT", "1")]), true, true).agent);
        assert!(!detect(false, env(&[("AI_AGENT", "")]), true, true).agent);
    }

    #[test]
    fn colours_only_people_at_a_terminal() {
        let s = detect(false, env(&[("WT_SESSION", "1")]), true, false);
        assert_eq!((s.color_out, s.color_err), (true, false));
        assert!(!detect(false, env(&[("NO_COLOR", "1"), ("WT_SESSION", "1")]), true, true).color_out);
        assert!(!detect(false, env(&[("NO_COLOR", "1"), ("CLICOLOR_FORCE", "1")]), true, true).color_out, "NO_COLOR wins");
        assert!(detect(false, env(&[("CLICOLOR_FORCE", "1")]), false, false).color_err);
        assert!(!detect(false, env(&[("CLICOLOR_FORCE", "0")]), false, false).color_err);
        assert!(!detect(true, env(&[("CLICOLOR_FORCE", "1")]), true, true).color_out, "agents get no colour");
        assert_eq!(paint(Color::Red, "x", true), "\x1b[1;31mx\x1b[0m");
        assert_eq!(paint(Color::Red, "x", false), "x");
    }

    #[test]
    fn registry_text_cannot_drive_the_terminal() {
        assert_eq!(printable("a\x1b]52;c;ZXZpbA==\x07b\nc"), "a ]52;c;ZXZpbA== b c");
        assert_eq!(printable("zażółć"), "zażółć");
        assert_eq!(lines("x 1.0\x1b[2J\n  y"), "x 1.0 [2J\n  y");
    }
}
