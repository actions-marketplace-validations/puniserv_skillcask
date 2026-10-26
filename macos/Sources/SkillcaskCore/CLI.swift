import Foundation

public struct RunResult: Sendable {
    public let command: String
    public let status: Int32
    public let stdout: Data
    public let stderr: String

    public init(command: String, status: Int32, stdout: Data, stderr: String) {
        self.command = command
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var ok: Bool { status == 0 }
    public var output: String {
        [String(decoding: stdout, as: UTF8.self), stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// A `--json` command prints its document even when it exits 1 (D32), so decode stdout
    /// whatever the exit code; nil when stdout holds no document.
    public func decode<T: Decodable>(_ type: T.Type) -> T? {
        try? JSONDecoder().decode(type, from: stdout)
    }
}

public enum CLI {
    /// Apps started from Finder get a minimal PATH, so the usual install locations are added.
    static let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.cargo/bin"]

    static var searchPath: [String] {
        let env = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        return env + extraPaths.filter { !env.contains($0) }
    }

    /// The configured path when it is executable, else the first `skillcask` on the search path.
    public static func locate(configured: String?) -> URL? {
        let fm = FileManager.default
        if let c = configured?.trimmingCharacters(in: .whitespaces), !c.isEmpty {
            let path = (c as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        return searchPath.map { URL(fileURLWithPath: $0).appendingPathComponent("skillcask") }
            .first { fm.isExecutableFile(atPath: $0.path) }
    }

    /// Runs `exe args` in `dir` with stdin closed, so skillcask never prompts (it only asks on a terminal).
    public static func run(_ exe: URL, _ args: [String], in dir: URL) async -> RunResult {
        let command = (["skillcask"] + args).joined(separator: " ")
        return await Task.detached {
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            p.currentDirectoryURL = dir
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = searchPath.joined(separator: ":")
            env["NO_COLOR"] = "1"
            p.environment = env
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            do {
                try p.run()
            } catch {
                return RunResult(command: command, status: -1, stdout: Data(), stderr: error.localizedDescription)
            }
            // Read stderr concurrently so a full pipe cannot block the child.
            let errData = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let stderr = String(decoding: await errData.value, as: UTF8.self)
            return RunResult(command: command, status: p.terminationStatus, stdout: outData, stderr: stderr)
        }.value
    }
}
