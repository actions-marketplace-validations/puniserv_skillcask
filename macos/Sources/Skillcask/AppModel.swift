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
    var doctor: DoctorDoc?
    var searchResults: [SearchDoc.Result] = []
    var last: RunResult?
    var busy = 0

    func open(_ url: URL) {
        let path = url.standardizedFileURL.path
        recent = Array(([path] + recent.filter { $0 != path }).prefix(10))
        UserDefaults.standard.set(recent, forKey: "recent")
        scope = .project(path)
    }

    func forget(_ path: String) {
        recent.removeAll { $0 == path }
        UserDefaults.standard.set(recent, forKey: "recent")
        if scope == .project(path) { scope = nil }
    }

    /// Runs skillcask in the current scope. `show` puts the result in the output pane; a failure
    /// always goes there, so stderr and the exit code are never swallowed.
    @discardableResult
    func run(_ args: [String], show: Bool = true) async -> RunResult? {
        guard let scope, let exe = locate() else { return nil }
        let (dir, flags): (URL, [String]) = switch scope {
        case .project(let p): (URL(fileURLWithPath: p), [])
        case .global: (FileManager.default.homeDirectoryForCurrentUser, ["-g"])
        }
        busy += 1
        defer { busy -= 1 }
        let r = await CLI.run(exe, flags + args, in: dir)
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
    }

    func loadInfo() async {
        info = nil
        guard selected?.state != "not managed", let target = selected?.package ?? selected?.skill else { return }
        info = await run(["info", "--json", target], show: false)?.decode(InfoDoc.self)
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
