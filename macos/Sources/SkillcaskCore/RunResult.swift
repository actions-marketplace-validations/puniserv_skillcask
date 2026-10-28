import Foundation

/// What one run of the CLI produced. `document(_:)` applies the one decoding rule of the app: a document on stdout
/// is a success whatever the exit code (D32: `status`, `outdated`, `doctor` and `audit` exit 1 with their document
/// when they found something); only the absence of a document makes the exit code matter.
public struct RunResult: Sendable {
    public let invocation: Invocation
    public let status: ExitStatus
    public let stdout: Data
    public let stderr: String
    public let duration: Duration
    /// The Settings environment names the child got (`EnvironmentPolicy.appliedOverrideNames`), set by
    /// `ProcessRunner`; names only, so a run record can say which overrides applied without showing a value.
    public var environmentOverrides: [String] = []

    public init(invocation: Invocation, status: ExitStatus, stdout: Data, stderr: String, duration: Duration = .zero) {
        self.invocation = invocation
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.duration = duration
    }

    public var report: StderrReport {
        StderrReport(parsing: stderr)
    }

    public var stdoutText: String {
        String(decoding: stdout, as: UTF8.self)
    }

    public func document<T: Decodable>(_ type: T.Type) throws(CLIError) -> T {
        if !stdout.isEmpty, let document = try? JSONDecoder().decode(type, from: stdout) {
            return document
        }
        if let failure = failure() {
            throw failure
        }
        if stdout.isEmpty {
            throw .noDocument
        }
        do {
            _ = try JSONDecoder().decode(type, from: stdout)
        } catch {
            throw .decode(String(describing: error), raw: stdout)
        }
        throw .decode("decoded on the second attempt", raw: stdout)
    }

    /// The error a non-zero exit stands for, nil on exit 0. For a mutation without `--json` this is the whole verdict.
    public func failure() -> CLIError? {
        switch status {
        case .exited(0):
            return nil
        case .exited(let code):
            let report = report
            let message = report.error ?? report.other.last ?? "skillcask exited with status \(code)"
            return .failed(code: ExitCode(code), message: message, hint: report.hint, stderr: stderr)
        case .signaled(let signal):
            return signal == SIGTERM ? .cancelled : .killed(signal: signal)
        }
    }
}
