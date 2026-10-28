import Foundation
import Testing

@testable import SkillcaskCore

@Suite struct RunResultTests {
    @Test(arguments: Fixture.versions) func exitOneWithADocumentIsASuccess(version: String) throws {
        let data = try Fixture.data(version, "status.problem.json")
        let result = RunResult(
            invocation: try Fixture.invocation(.status), status: .exited(1), stdout: data,
            stderr: "error: 1 problem(s)\n")
        let doc = try result.document(StatusDocument.self)
        #expect(!doc.ok)
        #expect(
            result.failure()
                == .failed(code: .problem, message: "1 problem(s)", hint: nil, stderr: "error: 1 problem(s)\n"))
    }

    @Test func exitZeroWithNothingIsNoDocument() throws {
        let result = try Fixture.result("")
        #expect(throws: CLIError.noDocument) { try result.document(StatusDocument.self) }
        #expect(result.failure() == nil)
    }

    @Test(arguments: Fixture.versions) func failureWithoutADocumentCarriesStderr(version: String) throws {
        let stderr = try Fixture.text(version, "status.noproject.stderr")
        let result = try Fixture.result("", status: .exited(1), stderr: stderr)
        #expect(
            throws: CLIError.failed(
                code: .problem, message: "skills.toml not found", hint: "run skillcask init", stderr: stderr)
        ) {
            try result.document(StatusDocument.self)
        }
    }

    @Test func failureWithoutAnErrorLineFallsBackToTheLastLineThenToTheCode() throws {
        let noisy = try Fixture.result("", status: .exited(3), stderr: "fetching x\ntimed out\n")
        #expect(
            noisy.failure()
                == .failed(code: .network, message: "timed out", hint: nil, stderr: "fetching x\ntimed out\n"))
        let silent = try Fixture.result("", status: .exited(101))
        #expect(
            silent.failure()
                == .failed(code: .other(101), message: "skillcask exited with status 101", hint: nil, stderr: ""))
    }

    @Test func undecodableStdoutOnExitZeroIsADecodeError() throws {
        let result = try Fixture.result("not json")
        #expect {
            try result.document(StatusDocument.self)
        } throws: { error in
            if case .decode(_, let raw) = error as? CLIError { raw == Data("not json".utf8) } else { false }
        }
    }

    @Test func undecodableStdoutOnFailureReportsTheFailure() throws {
        let result = try Fixture.result("partial {", status: .exited(5), stderr: "error: disk full\n")
        #expect(throws: CLIError.failed(code: .file, message: "disk full", hint: nil, stderr: "error: disk full\n")) {
            try result.document(StatusDocument.self)
        }
    }

    @Test func signals() throws {
        #expect(try Fixture.result("", status: .signaled(SIGTERM)).failure() == .cancelled)
        #expect(try Fixture.result("", status: .signaled(SIGKILL)).failure() == .killed(signal: SIGKILL))
        #expect(throws: CLIError.cancelled) {
            try Fixture.result("", status: .signaled(SIGTERM)).document(StatusDocument.self)
        }
    }

    @Test func exitStatusHelpers() {
        #expect(ExitStatus.exited(0).isSuccess && !ExitStatus.exited(1).isSuccess && !ExitStatus.signaled(9).isSuccess)
        #expect(ExitStatus.exited(4).code == 4 && ExitStatus.signaled(9).code == nil)
        #expect(OutputLine.stderr("x").text == "x")
    }
}
