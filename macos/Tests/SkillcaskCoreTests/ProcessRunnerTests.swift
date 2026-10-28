import Foundation
import Testing
import os

@testable import SkillcaskCore

/// Runs the fake `skillcask` script; serialized because every test spawns children and measures time.
@Suite(.serialized) struct ProcessRunnerTests {
    let scope = Scope.project(FileManager.default.temporaryDirectory.standardizedFileURL)

    func runner(mode: String? = nil, limits: ProcessRunner.Limits = ProcessRunner.Limits()) -> ProcessRunner {
        var overrides = ["FAKE_FIXTURES": Fixture.root.path]
        if let mode {
            overrides["FAKE_MODE"] = mode
        }
        return ProcessRunner(
            executable: Fixture.fakeCLI, policy: EnvironmentPolicy(overrides: overrides), limits: limits)
    }

    func status(in scope: Scope? = nil) throws -> Invocation {
        try Fixture.invocation(.status, in: scope ?? self.scope)
    }

    @Test func statusDocumentFromTheScript() async throws {
        let result = try await runner().run(status())
        #expect(result.status == .exited(0))
        #expect(try result.document(StatusDocument.self).entries.count == 3)
        #expect(result.duration > .zero)
    }

    @Test func exitOneWithADocument() async throws {
        let result = try await runner(mode: "problem").run(status())
        #expect(result.status == .exited(1))
        #expect(try !result.document(StatusDocument.self).ok)
    }

    @Test func errorAndHintOnStderr() async throws {
        let result = try await runner(mode: "fail").run(status())
        #expect(result.status == .exited(3) && result.stdout.isEmpty)
        #expect(result.stderr == "error: package acme/none not found\n  hint: run skillcask init\n")
        #expect(
            result.failure()
                == .failed(
                    code: .network, message: "package acme/none not found", hint: "run skillcask init",
                    stderr: result.stderr))
    }

    @Test(.timeLimit(.minutes(1))) func bothStreamsAreDrainedAndStreamedInOrder() async throws {
        let lines = OSAllocatedUnfairLock(initialState: [OutputLine]())
        let result = try await runner(mode: "both").run(status()) { line in lines.withLock { $0.append(line) } }
        #expect(result.stdoutText.split(separator: "\n").count == 2000)
        #expect(result.stderr.split(separator: "\n").count == 2000)
        let seen = lines.withLock { $0 }
        let out = seen.compactMap { if case .stdout(let text) = $0 { text } else { nil } }
        let err = seen.compactMap { if case .stderr(let text) = $0 { text } else { nil } }
        #expect(out == (0..<2000).map { "out \($0)" })
        #expect(err == (0..<2000).map { "err \($0)" })
    }

    @Test(.timeLimit(.minutes(1))) func largeOutputIsDrained() async throws {
        let result = try await runner(mode: "big").run(status())
        #expect(result.stdout.count == 300_001)
    }

    @Test(.timeLimit(.minutes(1))) func outputBeyondTheCapIsAnError() async throws {
        var limits = ProcessRunner.Limits()
        limits.stdoutBytes = 1 << 20
        await #expect(throws: CLIError.outputTooLarge(limit: 1 << 20)) {
            try await runner(mode: "flood", limits: limits).run(status())
        }
    }

    @Test(.timeLimit(.minutes(1))) func cancelTerminatesTheChild() async throws {
        let runner = runner(mode: "sleep")
        let invocation = try status()
        let task = Task { try await runner.run(invocation) }
        try await Task.sleep(for: .milliseconds(300))
        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        await #expect(throws: CLIError.cancelled) { try await task.value }
        #expect(clock.now - start < .seconds(4))
        #expect(await runner.runningCount == 0)
    }

    @Test(.timeLimit(.minutes(1))) func aChildIgnoringSIGTERMIsKilledAfterTheGrace() async throws {
        var limits = ProcessRunner.Limits()
        limits.grace = .milliseconds(200)
        let runner = runner(mode: "stubborn", limits: limits)
        let invocation = try status()
        let task = Task { try await runner.run(invocation) }
        try await Task.sleep(for: .milliseconds(300))
        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        await #expect(throws: CLIError.cancelled) { try await task.value }
        #expect(clock.now - start < .seconds(3))
    }

    @Test func environmentPolicyReachesTheChild() async throws {
        let result = try await runner(mode: "env").run(status())
        let env = Dictionary(
            result.stdoutText.split(separator: "\n")
                .compactMap { line -> (String, String)? in
                    guard let eq = line.firstIndex(of: "=") else { return nil }
                    return (String(line[..<eq]), String(line[line.index(after: eq)...]))
                }, uniquingKeysWith: { first, _ in first })
        #expect(env["NO_COLOR"] == "1" && env["SKILLCASK_AGENT"] == "0")
        #expect(env["CLICOLOR_FORCE"] == nil && env["CLAUDECODE"] == nil)
        #expect(env["PATH"]?.contains("/opt/homebrew/bin") == true)
        #expect(env["FAKE_MODE"] == "env")
    }

    /// A runner over a shared `EnvironmentSource` reads it at every spawn: a change reaches the next run.
    @Test func sharedSourceReachesTheNextRun() async throws {
        let source = EnvironmentSource(
            EnvironmentPolicy(overrides: ["FAKE_FIXTURES": Fixture.root.path, "FAKE_MODE": "env", "X_SET": "1"]))
        let runner = ProcessRunner(executable: Fixture.fakeCLI, source: source)
        #expect(try await runner.run(status()).stdoutText.contains("X_SET=1\n"))
        source.policy.overrides["X_SET"] = "2"
        #expect(try await runner.run(status()).stdoutText.contains("X_SET=2\n"))
        #expect(runner.policy.overrides["X_SET"] == "2")
    }

    /// The run record names the overrides the child got, never their values.
    @Test func runRecordNamesTheAppliedOverrides() async throws {
        let source = EnvironmentSource(
            EnvironmentPolicy(
                overrides: [
                    "FAKE_FIXTURES": Fixture.root.path, "FAKE_MODE": "status", "HTTPS_PROXY": "http://secret:1",
                    "GITHUB_TOKEN": "refused",
                ]))
        let result = try await ProcessRunner(executable: Fixture.fakeCLI, source: source).run(status())
        #expect(result.environmentOverrides == ["FAKE_FIXTURES", "FAKE_MODE", "HTTPS_PROXY"])
    }

    @Test func argvAndWorkingDirectory() async throws {
        let args = try await runner(mode: "args").run(status(in: .personal))
        #expect(args.stdoutText == "-g\nstatus\n--json\n")
        let cwd = try await runner(mode: "cwd").run(status(in: .project(at: "/private/tmp")))
        #expect(cwd.stdoutText == "/private/tmp\n")
    }

    @Test func stdinTextIsWrittenAndClosed() async throws {
        let invocation = try Invocation(
            .authSet(host: "h", username: nil), in: scope, capabilities: Fixture.capabilities, stdin: .text("tok\n"))
        let result = try await runner(mode: "stdin").run(invocation)
        #expect(result.stdoutText == "tok\n")
        let nothing = try await runner(mode: "stdin").run(status())
        #expect(nothing.stdoutText.isEmpty && nothing.status == .exited(0))
    }

    /// A child that exits without reading its stdin leaves the write without a reader: EPIPE, not a SIGPIPE that
    /// would kill the test process (and the app). The run ends with the child's own exit.
    @Test(.timeLimit(.minutes(1))) func stdinToAChildThatExitedEarlyIsNotFatal() async throws {
        let text = String(repeating: "x", count: 1 << 20)
        let invocation = try Invocation(
            .authSet(host: "h", username: nil), in: scope, capabilities: Fixture.capabilities, stdin: .text(text))
        for _ in 0..<5 {
            let result = try await runner(mode: "quit").run(invocation)
            #expect(result.status == .exited(0) && result.stdout.isEmpty)
        }
    }

    @Test func missingExecutableFailsToLaunch() async throws {
        let runner = ProcessRunner(executable: URL(fileURLWithPath: "/nonexistent/skillcask"))
        await #expect {
            try await runner.run(status())
        } throws: { error in
            if case .launchFailed = error as? CLIError { true } else { false }
        }
    }

    @Test func versionGateThroughTheClient() async throws {
        let version = try Fixture.invocation(.version, in: scope)
        #expect(try await runner().capabilities(via: version) == Capabilities(version: Version(0, 9, 4)))
        await #expect(throws: CLIError.tooOld(found: Version(0, 8, 0), needs: Version(0, 9, 4))) {
            try await runner(mode: "old").capabilities(via: version)
        }
        await #expect {
            try await runner(mode: "fail").capabilities(via: version)
        } throws: { error in
            if case .unreadableVersion(let output) = error as? CLIError { output.hasPrefix("error:") } else { false }
        }
    }

    @Test func documentHelperDecodesInOneStep() async throws {
        let doc = try await runner().document(StatusDocument.self, for: status())
        #expect(doc.ok)
    }
}
