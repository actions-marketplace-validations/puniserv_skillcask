import Foundation
import SkillcaskCore

/// Documents captured from real CLI releases (`Fixtures/README.md` says how) and the fake `skillcask` script.
enum Fixture {
    static let root: URL = {
        guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            fatalError("Fixtures directory missing from the test bundle")
        }
        return url
    }()

    /// Every `<version>/` directory, oldest first.
    static let versions: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { $0.first?.isNumber == true }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    }()

    static func url(_ version: String, _ name: String) -> URL {
        root.appending(path: "\(version)/\(name)")
    }

    static func data(_ version: String, _ name: String) throws -> Data {
        try Data(contentsOf: url(version, name))
    }

    static func text(_ version: String, _ name: String) throws -> String {
        try String(contentsOf: url(version, name), encoding: .utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ version: String, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: data(version, "\(name).json"))
    }

    static let capabilities = Capabilities(version: Capabilities.minimum)

    /// The fake CLI script, copied into the bundle with its executable bit.
    static let fakeCLI = root.appending(path: "bin/skillcask")

    static func invocation(
        _ command: Invocation.Command, in scope: Scope = .project(URL(fileURLWithPath: "/tmp/p"))
    ) throws -> Invocation {
        try Invocation(command, in: scope, capabilities: capabilities)
    }

    static func result(_ json: String, status: ExitStatus = .exited(0), stderr: String = "") throws -> RunResult {
        RunResult(invocation: try invocation(.status), status: status, stdout: Data(json.utf8), stderr: stderr)
    }
}
