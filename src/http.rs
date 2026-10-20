//! HTTPS-only client with Composer `auth.json` credentials.

use std::path::{Path, PathBuf};
use std::time::Duration;

use base64::Engine as _;
use serde_json::Value;
use ureq::tls::{PemItem, RootCerts, TlsConfig};
use url::Url;

use crate::bail;
use crate::error::{AUTH, Error, IO, NETWORK, Result};

const MAX_REDIRECTS: usize = 5;
const JSON_LIMIT: u64 = 50 * 1024 * 1024;

#[derive(Clone, Debug, PartialEq)]
enum Cred {
    Basic(String, String),
    Bearer(String),
    PrivateToken(String),
}

impl Cred {
    fn header(&self) -> (&'static str, String) {
        match self {
            Cred::Basic(u, p) => {
                ("Authorization", format!("Basic {}", base64::engine::general_purpose::STANDARD.encode(format!("{u}:{p}"))))
            }
            Cred::Bearer(t) => ("Authorization", format!("Bearer {t}")),
            Cred::PrivateToken(t) => ("PRIVATE-TOKEN", t.clone()),
        }
    }
}

/// Entries in source priority order; the first entry for a host wins.
#[derive(Debug, Default)]
struct Auth(Vec<(String, Cred)>);

impl Auth {
    fn load(config: &Path) -> Result<Auth> {
        let home = std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")).map(PathBuf::from);
        let composer_home = std::env::var_os("COMPOSER_HOME").map(PathBuf::from);
        let global = match (composer_home, home) {
            (Some(c), _) => Some(c.join("auth.json")),
            (None, Some(h)) => [h.join(".composer/auth.json"), h.join(".config/composer/auth.json")].into_iter().find(|p| p.exists()),
            _ => None,
        };
        let mut auth = Auth::default();
        if let Ok(env) = std::env::var("COMPOSER_AUTH") {
            auth.add(&env, "COMPOSER_AUTH")?;
        }
        for path in std::iter::once(config.join("auth.json")).chain(global) {
            match std::fs::read_to_string(&path) {
                Ok(text) => auth.add(&text, &path.display().to_string())?,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                Err(e) => return Err(e.into()),
            }
        }
        let token = ["GITHUB_TOKEN", "GH_TOKEN"].iter().find_map(|k| std::env::var(k).ok().filter(|t| !t.is_empty()));
        if let (Some(t), Some(host)) = (token, Url::parse(&crate::github::api()).ok().and_then(|u| u.host_str().map(String::from))) {
            auth.0.push((host, Cred::Bearer(t)));
        }
        Ok(auth)
    }

    fn add(&mut self, json: &str, source: &str) -> Result<()> {
        let bad = || Error::new(AUTH, format!("{source}: invalid auth JSON"));
        let v: Value = serde_json::from_str(json).map_err(|_| bad())?;
        let section = |k: &str| v.get(k).and_then(Value::as_object).into_iter().flatten();
        let str_or = |v: &Value, k: &str| v.as_str().or_else(|| v.get(k).and_then(Value::as_str)).map(String::from);
        for (host, c) in section("http-basic") {
            let user = c.get("username").and_then(Value::as_str).ok_or_else(bad)?;
            let pass = c.get("password").and_then(Value::as_str).unwrap_or("");
            self.0.push((host.clone(), Cred::Basic(user.into(), pass.into())));
        }
        for (host, c) in section("bearer") {
            self.0.push((host.clone(), Cred::Bearer(c.as_str().ok_or_else(bad)?.into())));
        }
        for (host, c) in section("gitlab-token") {
            self.0.push((host.clone(), Cred::PrivateToken(str_or(c, "token").ok_or_else(bad)?)));
        }
        for (host, c) in section("gitlab-oauth") {
            self.0.push((host.clone(), Cred::Bearer(str_or(c, "token").ok_or_else(bad)?)));
        }
        for (host, c) in section("github-oauth") {
            let token = Cred::Bearer(c.as_str().ok_or_else(bad)?.into());
            // Composer keys the token by github.com; the API that skillcask calls lives on api.github.com.
            if host.eq_ignore_ascii_case("github.com") {
                self.0.push(("api.github.com".into(), token.clone()));
            }
            self.0.push((host.clone(), token));
        }
        Ok(())
    }

    fn lookup(&self, url: &Url) -> Option<&Cred> {
        let host = url.host_str()?;
        let with_port = url.port().map(|p| format!("{host}:{p}"));
        let find = |h: &str| self.0.iter().find(|(k, _)| k.eq_ignore_ascii_case(h)).map(|(_, c)| c);
        with_port.as_deref().and_then(find).or_else(|| find(host))
    }
}

/// URL safe to print: no userinfo, no query (tokens sometimes travel there).
pub fn redact(url: &Url) -> String {
    let mut u = url.clone();
    let _ = u.set_username("");
    let _ = u.set_password(None);
    if u.query().is_some() {
        u.set_query(Some("…"));
    }
    u.to_string()
}

pub struct Http {
    agent: ureq::Agent,
    auth: Auth,
    verbose: bool,
}

impl Http {
    pub fn new(config: &Path, verbose: bool) -> Result<Http> {
        let roots = match std::env::var_os("SKILLCASK_CA_FILE") {
            None => RootCerts::PlatformVerifier,
            Some(path) => {
                let pem =
                    std::fs::read(&path).map_err(|e| Error::new(IO, format!("SKILLCASK_CA_FILE {}: {e}", Path::new(&path).display())))?;
                let certs: Vec<_> = ureq::tls::parse_pem(&pem)
                    .filter_map(|i| match i {
                        Ok(PemItem::Certificate(c)) => Some(c),
                        _ => None,
                    })
                    .collect();
                if certs.is_empty() {
                    bail!(IO, "SKILLCASK_CA_FILE {}: no certificates found", Path::new(&path).display());
                }
                RootCerts::from(certs)
            }
        };
        let agent = ureq::Agent::config_builder()
            .tls_config(TlsConfig::builder().root_certs(roots).build())
            .https_only(true)
            .http_status_as_error(false)
            .max_redirects(0)
            .max_redirects_will_error(false)
            .timeout_global(Some(Duration::from_secs(300)))
            .user_agent(concat!("skillcask/", env!("CARGO_PKG_VERSION")))
            .build()
            .into();
        Ok(Http { agent, auth: Auth::load(config)?, verbose })
    }

    /// `Ok(None)` on 404/410.
    pub fn get(&self, url: &str, max_bytes: u64) -> Result<Option<Vec<u8>>> {
        let mut cur = Url::parse(url).map_err(|e| Error::new(NETWORK, format!("invalid URL {url:?}: {e}")))?;
        for _ in 0..=MAX_REDIRECTS {
            if cur.scheme() != "https" {
                bail!(NETWORK, "refusing non-HTTPS URL {}", redact(&cur));
            }
            let shown = redact(&cur);
            if self.verbose {
                eprintln!("GET {shown}");
            }
            let inline =
                (!cur.username().is_empty()).then(|| Cred::Basic(cur.username().to_string(), cur.password().unwrap_or("").to_string()));
            let _ = cur.set_username("");
            let _ = cur.set_password(None);
            let mut req = self.agent.get(cur.as_str());
            if let Some(c) = inline.as_ref().or_else(|| self.auth.lookup(&cur)) {
                let (k, v) = c.header();
                req = req.header(k, v);
            }
            let mut resp = req.call().map_err(|e| Error::new(NETWORK, format!("{shown}: {e}")))?;
            let status = resp.status().as_u16();
            match status {
                200..=299 => {
                    return match resp.body_mut().with_config().limit(max_bytes).read_to_vec() {
                        Ok(b) => Ok(Some(b)),
                        Err(ureq::Error::BodyExceedsLimit(_)) => {
                            Err(Error::new(IO, format!("{shown}: response exceeds the limit of {max_bytes} bytes")))
                        }
                        Err(e) => Err(Error::new(NETWORK, format!("{shown}: {e}"))),
                    };
                }
                301 | 302 | 303 | 307 | 308 => {
                    let loc = resp
                        .headers()
                        .get("location")
                        .and_then(|v| v.to_str().ok())
                        .ok_or_else(|| Error::new(NETWORK, format!("{shown}: redirect without Location")))?;
                    cur = cur.join(loc).map_err(|e| Error::new(NETWORK, format!("{shown}: bad redirect: {e}")))?;
                }
                404 | 410 => return Ok(None),
                401 | 403 => bail!(
                    AUTH,
                    "{shown}: HTTP {status}; check auth.json / COMPOSER_AUTH for {} (GitHub: GITHUB_TOKEN, also for the anonymous rate limit)",
                    cur.host_str().unwrap_or("")
                ),
                _ => bail!(NETWORK, "{shown}: HTTP {status}"),
            }
        }
        bail!(NETWORK, "{}: more than {MAX_REDIRECTS} redirects", redact(&cur))
    }

    pub fn get_json(&self, url: &str) -> Result<Option<Value>> {
        match self.get(url, JSON_LIMIT)? {
            None => Ok(None),
            Some(b) => serde_json::from_slice(&b).map(Some).map_err(|e| {
                Error::new(NETWORK, format!("{}: invalid JSON: {e}", Url::parse(url).map(|u| redact(&u)).unwrap_or_default()))
            }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auth_sources_and_host_matching() {
        let mut a = Auth::default();
        a.add(
            r#"{"http-basic":{"git.example.com":{"username":"gitlab-ci-token","password":"job"}},"bearer":{"repo.example.com:8443":"b1"}}"#,
            "env",
        )
        .unwrap();
        a.add(r#"{"http-basic":{"git.example.com":{"username":"other","password":"x"}},"gitlab-token":{"gl.example.com":{"username":"u","token":"pt"}},"gitlab-oauth":{"oa.example.com":"ot"},"bearer":{"repo.example.com":"b2"},"github-oauth":{"github.com":"gh"}}"#, "file").unwrap();
        let get = |u: &str| a.lookup(&Url::parse(u).unwrap()).cloned();
        assert_eq!(get("https://git.example.com/x"), Some(Cred::Basic("gitlab-ci-token".into(), "job".into())));
        assert_eq!(get("https://repo.example.com:8443/x"), Some(Cred::Bearer("b1".into())));
        assert_eq!(get("https://repo.example.com/x"), Some(Cred::Bearer("b2".into())));
        assert_eq!(get("https://gl.example.com/x"), Some(Cred::PrivateToken("pt".into())));
        assert_eq!(get("https://oa.example.com/x"), Some(Cred::Bearer("ot".into())));
        assert_eq!(get("https://api.github.com/repos/a/b"), Some(Cred::Bearer("gh".into())));
        assert_eq!(get("https://none.example.com/x"), None);
        assert_eq!(Cred::Basic("a".into(), "b".into()).header().1, "Basic YTpi");
        assert!(a.add("not json", "x").is_err());
        assert!(a.add(r#"{"bearer":{"h":5}}"#, "x").is_err());
    }

    #[test]
    fn redacts_credentials() {
        let u = Url::parse("https://user:secret@h.example.com/p.json?private_token=abc").unwrap();
        let r = redact(&u);
        assert!(!r.contains("secret") && !r.contains("user") && !r.contains("abc"), "{r}");
        assert!(r.starts_with("https://h.example.com/p.json"));
    }

    #[test]
    fn refuses_plain_http_before_any_request() {
        let http = Http::new(Path::new("/nonexistent"), false).unwrap();
        let e = http.get("http://example.com/packages.json", 10).unwrap_err();
        assert_eq!(e.code, NETWORK);
        assert!(e.msg.contains("refusing non-HTTPS"));
    }
}
