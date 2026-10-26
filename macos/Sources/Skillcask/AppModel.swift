import Foundation
import Observation
import SkillcaskCore

@MainActor @Observable
final class AppModel {
    enum Scope: Hashable {
        case project(String)
        case global
    }

    var scope: Scope?
    var recent: [String] = UserDefaults.standard.stringArray(forKey: "recent") ?? []
    var status: StatusDoc?
    var outdated: [String: OutdatedDoc.Package] = [:]
    var needsInit = false
    var tooOld: String?
    var selected: StatusDoc.Entry?
    var info: InfoDoc?
    var audit: [String: AuditDoc.Skill] = [:]
    var skillText: String?
    var diff: (package: String, text: String)?
    var doctor: DoctorDoc?
    var searchResults: [SearchDoc.Result] = []
    var last: RunResult?
    var busy = 0
    var scanning = false

    func open(_ url: URL) {
        let path = url.standardizedFileURL.path
        recent = [path] + recent.filter { $0 != path }
        UserDefaults.standard.set(recent, forKey: "recent")
        scope = .project(path)
    }

    /// Adds every project `skillcask projects` finds under `root` to the list.
    func scan(_ root: URL) async {
        guard let exe = locate() else { return }
        scanning = true
        defer { scanning = false }
        let r = await CLI.run(exe, ["projects", "--json", root.path], in: root)
        guard r.ok, let doc = r.decode(ProjectsDoc.self) else {
            last = r
            return
        }
        recent += doc.projects.map(\.path).filter { !recent.contains($0) }
        UserDefaults.standard.set(recent, forKey: "recent")
    }

    func forget(_ path: String) {
        recent.removeAll { $0 == path }
        UserDefaults.standard.set(recent, forKey: "recent")
        if scope == .project(path) { scope = nil }
    }

    /// The directory skillcask runs in, and the one the paths of its documents are relative to.
    private var root: URL? {
        switch scope {
        case .project(let p): URL(fileURLWithPath: p)
        case .global: FileManager.default.homeDirectoryForCurrentUser
        case nil: nil
        }
    }

    /// Runs skillcask in the current scope. `show` puts the result in the output pane; a failure
    /// always goes there, so stderr and the exit code are never swallowed.
    @discardableResult
    func run(_ args: [String], show: Bool = true) async -> RunResult? {
        guard let root, let exe = locate() else { return nil }
        busy += 1
        defer { busy -= 1 }
        let r = await CLI.run(exe, (scope == .global ? ["-g"] : []) + args, in: root)
        if show || !r.ok { last = r }
        return r
    }

    private func locate() -> URL? {
        guard let exe = CLI.locate(configured: UserDefaults.standard.string(forKey: "skillcaskPath")) else {
            last = RunResult(
                command: "skillcask", status: -1, stdout: Data(),
                stderr: "skillcask not found on PATH, in /opt/homebrew/bin or /usr/local/bin, or at the path set in Settings")
            return nil
        }
        return exe
    }

    func refresh() async {
        status = nil
        outdated = [:]
        audit = [:]
        selected = nil
        info = nil
        needsInit = false
        tooOld = nil
        // An older binary rejects `--json` with a usage error that explains nothing.
        guard let exe = locate() else { return }
        let v = await CLI.run(exe, ["--version"], in: FileManager.default.homeDirectoryForCurrentUser)
        tooOld = CLI.tooOld(String(decoding: v.stdout, as: UTF8.self))
        if tooOld != nil { return }
        if case .project(let p) = scope, !FileManager.default.fileExists(atPath: p + "/skills.toml") {
            needsInit = true
            return
        }
        status = await run(["status", "--json"], show: false)?.decode(StatusDoc.self)
        let o = await run(["outdated", "--json"], show: false)?.decode(OutdatedDoc.self)
        outdated = Dictionary(o?.packages.map { ($0.package, $0) } ?? [], uniquingKeysWith: { a, _ in a })
        await loadAudit()
    }

    /// `audit` exits 1 when it has findings; only a run without a document is a failure.
    private func loadAudit() async {
        let saved = last
        guard let doc = await run(["audit", "--json"], show: false)?.decode(AuditDoc.self) else { return }
        last = saved
        audit = Dictionary(doc.skills.map { ($0.skill, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func loadInfo() async {
        info = nil
        skillText = nil
        guard selected?.state != "not managed", let target = selected?.package ?? selected?.skill else { return }
        // The one file the app reads itself, at the path audit reports (info has none for package skills).
        if let path = selected?.skill.flatMap({ audit[$0]?.path }), let root {
            skillText = try? String(contentsOf: root.appendingPathComponent(path + "/SKILL.md"), encoding: .utf8)
        }
        info = await run(["info", "--json", target], show: false)?.decode(InfoDoc.self)
    }

    /// Shows what `update package` would change before running it.
    func showDiff(_ package: String) async {
        guard let r = await run(["diff", package], show: false), r.ok else { return }
        diff = (package, String(decoding: r.stdout, as: UTF8.self))
    }

    /// A command that changes the project, followed by a fresh status.
    func change(_ args: [String]) async {
        await run(args)
        await refresh()
    }

    func search(_ query: String) async {
        searchResults = await run(["search", "--json", query], show: false)?.decode(SearchDoc.self)?.results ?? []
    }

    func runDoctor(fix: Bool = false) async {
        doctor = await run(["doctor", "--json"] + (fix ? ["--fix"] : []), show: fix)?.decode(DoctorDoc.self)
    }
}
