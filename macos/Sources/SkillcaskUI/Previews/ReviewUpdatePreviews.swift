import Foundation
import SkillcaskCore
import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// The Review Update sheet at `Size.reviewSheet` over the api scope's fixtures: the ReviewUpdate board's
    /// pdf 1.2.0 → 1.4.0 and every ReviewUpdate-States state, plus loading and review-only (tag moved).
    ///
    /// A pending update shows no flags (Q11 interim: `audit` describes only the installed version). `flags-planned`
    /// is the one planned-capability state: seeded findings of the new version (risky line 12, invisible line 13
    /// of pdf/SKILL.md) as the CLI would give them, to show the board's outline, amber dot and callout.
    static let reviewUpdate: [Entry] = [
        reviewEntry("review") {
            ReviewUpdateSample.prepared(.package("anthropics/skills", version: "1.4.0", reviewOnly: false)) {
                $0.preload(DesignFixtures.pdfDiff)
            }
        },
        reviewEntry("update-all") {
            ReviewUpdateSample.prepared(.all) {
                $0.preload(DesignFixtures.updateAllDiff)
            }
        },
        reviewEntry("up-to-date") {
            ReviewUpdateSample.prepared(
                .package("pdf", version: nil, reviewOnly: false), snapshot: DesignFixtures.apiUpdated
            ) {
                $0.preload(DesignFixtures.upToDateDiff)
            }
        },
        reviewEntry("fetch-failed") {
            ReviewUpdateSample.prepared(.package("anthropics/skills", version: "1.4.0", reviewOnly: false)) {
                $0.preload(failure: ReviewUpdateSample.fetchError)
            }
        },
        // Planned capability, not today's behaviour: findings of the NEW version from the CLI (Q11). A pending
        // update shows no flags until then; this state shows the board's outline, dot and callout for that day.
        reviewEntry("flags-planned") {
            ReviewUpdateSample.prepared(.package("anthropics/skills", version: "1.4.0", reviewOnly: false)) {
                $0.preload(DesignFixtures.pdfDiff, newVersionFindings: ReviewUpdateSample.pdfFindings)
            }
        },
        reviewEntry("progress") { ReviewUpdateSample.progress() },
        // An integrity failure (exit 4) with Details disclosing the run's transcript in the sheet; no Retry.
        reviewEntry("integrity-details") { ReviewUpdateSample.integrityFailure() },
        // jira's 4.3.0 is inside the range but waits for the minimum release age: nothing to update.
        // The Versions cooldown's "Read the changes…": `diff --to 4.3.0`, review-only, Done instead of Update.
        reviewEntry("read-waiting") {
            ReviewUpdateSample.prepared(
                .package("netresearch/agent-jira-skill", version: "4.3.0", reviewOnly: true)
            ) {
                $0.preload(UnifiedDiff(text: DesignFixtures.text("diff.jira-communication", "txt")))
            }
        },
        reviewEntry("cooldown") {
            ReviewUpdateSample.prepared(.package("jira-communication", version: nil, reviewOnly: false)) {
                $0.preload(DesignFixtures.upToDateDiff)
            }
        },
        reviewEntry("loading") { ReviewUpdateSample.loading() },
        reviewEntry("review-only") {
            ReviewUpdateSample.prepared(
                .package("juliusbrussee/caveman", version: "4.1.0", reviewOnly: true),
                snapshot: DesignFixtures.apiTagMoved
            ) {
                $0.preload(UnifiedDiff(text: ReviewUpdateSample.cavemanDiff))
            }
        },
    ]

    private static func reviewEntry(_ state: String, _ make: @escaping @MainActor @Sendable () -> AnyView) -> Entry {
        Entry(id: "P3-8", state: state, size: Size.reviewSheet, make: make)
    }
}

/// Builders of the sheet's states over a fixture scope store: a prepared review where the state is data, the
/// window's route (`SheetHost`) for loading, a real run for progress. Loading and progress talk to
/// `PendingCLIClient`, whose `diff` never answers and whose `update` prints the board's transcript and keeps
/// running, so the render shows them in flight.
@MainActor private enum ReviewUpdateSample {
    /// The sheet with its review prepared by `prepare`.
    static func prepared(
        _ target: ReviewUpdateSheet.Target, snapshot: ScopeSnapshot = DesignFixtures.api,
        _ prepare: (ReviewStore) -> Void
    ) -> AnyView {
        let store = store(snapshot)
        let review = ReviewUpdateSheet.review(for: target, store: store)
        prepare(review)
        return AnyView(
            ReviewUpdateSheet(target: target, store: store, onClose: {}, review: review)
                .environment(ActionRunner(queue: MutationQueue())))
    }

    /// The sheet as the window opens it from pdf's row, while `diff` is still running.
    static func loading() -> AnyView {
        AnyView(
            SheetHost(
                sheet: .update(package: "anthropics/skills", target: "1.4.0", reviewOnly: false),
                store: store(DesignFixtures.api, client: PendingCLIClient()), onClose: {}
            )
            .environment(ActionRunner(queue: MutationQueue())))
    }

    /// Update pressed: the sheet's run in flight with the board's transcript.
    static func progress() -> AnyView {
        let target = ReviewUpdateSheet.Target.package("anthropics/skills", version: "1.4.0", reviewOnly: false)
        let store = store(DesignFixtures.api, client: PendingCLIClient())
        let runner = ActionRunner(queue: MutationQueue())
        let review = ReviewUpdateSheet.review(for: target, store: store)
        review.preload(DesignFixtures.pdfDiff)
        let run = SheetRun()
        review.update(with: run, in: store, runner: runner, onSuccess: {})
        return AnyView(
            ReviewUpdateSheet(target: target, store: store, onClose: {}, review: review, run: run)
                .environment(runner))
    }

    /// Update pressed and failed with exit 4: the banner, Details open on the recorded run's transcript.
    static func integrityFailure() -> AnyView {
        let target = ReviewUpdateSheet.Target.package("anthropics/skills", version: "1.4.0", reviewOnly: false)
        let store = store(DesignFixtures.api)
        let runner = ActionRunner(queue: MutationQueue())
        let review = ReviewUpdateSheet.review(for: target, store: store)
        review.preload(DesignFixtures.pdfDiff)
        let error = CLIError.failed(
            code: .integrity, message: "The downloaded content did not match the lock. Nothing was changed.",
            hint: "This can mean the source was tampered with. Tell whoever maintains anthropics/skills before "
                + "trying again.",
            stderr: "error: anthropics/skills 1.4.0: sha256 mismatch\n")
        let transcript =
            Array(DesignFixtures.Transcripts.updatePdf.prefix(3)).map(OutputLine.stdout) + [
                .stderr("error: anthropics/skills 1.4.0: sha256 mismatch"),
                .stderr("hint: This can mean the source was tampered with."),
            ]
        let command =
            (try? Invocation(
                .update(packages: ["anthropics/skills"]), in: Boot.apiScope,
                capabilities: Capabilities(version: Capabilities.minimum)))?
            .displayCommand ?? ActionCopy.unbuilt
        let failure = ReviewUpdateCopy.couldNotUpdate("pdf")
        let entry = ActionRunner.ActivityEntry(
            title: review.runTitle, headline: failure, command: command, scope: Boot.apiScope,
            startedAt: Date(timeIntervalSinceNow: -4), duration: .seconds(4), status: .exited(4), error: error,
            transcript: transcript, isMutation: true, expectsDocument: false)
        runner.preloadActivity([entry], shown: false)
        let run = SheetRun()
        run.preload(phase: .failed(ErrorCopy.message(for: error, title: failure)), runID: entry.id, runner: runner)
        return AnyView(
            ReviewUpdateSheet(
                target: target, store: store, onClose: {}, review: review, run: run, showsRunDetails: true
            )
            .environment(runner))
    }

    /// The api scope with `snapshot` and pdf's detail (its `info` gives the range `^1.2`).
    static func store(_ snapshot: ScopeSnapshot, client: any CLIClient = FixtureCLIClient()) -> ScopeStore {
        let store = ScopeStore(
            scope: Boot.apiScope, client: client, capabilities: Capabilities(version: Capabilities.minimum))
        store.preload(
            snapshot: snapshot, selection: "pdf",
            detail: SkillDetail(info: DesignFixtures.pdfInfo, text: DesignFixtures.pdfText))
        return store
    }

    /// `github.com did not answer.` (ReviewUpdate-States); the app adds what to do and that nothing changed.
    static let fetchError = CLIError.failed(
        code: .network, message: "github.com did not answer.", hint: nil,
        stderr: "error: github.com did not answer: operation timed out after 30 s\n")

    /// The board's two flagged lines of pdf/SKILL.md as findings of the new version (planned capability).
    static let pdfFindings: [String: [AuditDocument.Finding]] = {
        let json = """
            [{"rule": "risky-pattern", "path": ".skillcask/skills/pdf/SKILL.md", "line": 12,
              "message": "downloads code into a shell"},
             {"rule": "invisible-character", "path": ".skillcask/skills/pdf/SKILL.md", "line": 13,
              "message": "U+202E RIGHT-TO-LEFT OVERRIDE"}]
            """
        let findings = (try? JSONDecoder().decode([AuditDocument.Finding].self, from: Data(json.utf8))) ?? []
        return ["anthropics/skills": findings]
    }()

    /// caveman's moved tag v4.1.0 (Versions-States): a small diff in the CLI's shape.
    static let cavemanDiff = """
        juliusbrussee/caveman 4.0.1 -> 4.1.0
        --- a/caveman/SKILL.md
        +++ b/caveman/SKILL.md
        @@ -1,6 +1,7 @@
         ---
         name: caveman
        -description: Talk like caveman. Few words.
        +description: Talk like caveman. Few words, fewer tokens.
         ---

         Use short words.
        +Drop articles and filler.
        """
}

/// A CLI that is still working: `diff` never answers, `update` prints the board's transcript and keeps running;
/// both end only when cancelled. Previews only.
private struct PendingCLIClient: CLIClient {
    func run(
        _ invocation: Invocation, onLine: @escaping @Sendable (OutputLine) -> Void
    ) async throws(CLIError) -> RunResult {
        if case .update = invocation.command {
            for line in DesignFixtures.Transcripts.updatePdf {
                onLine(.stdout(line))
            }
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
        }
        throw .cancelled
    }
}
