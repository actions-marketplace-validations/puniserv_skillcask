import Foundation
import SkillcaskCore
import SkillcaskDomain
import Testing

@testable import SkillcaskUI

/// The Review Update sheet's model (P3-8) over a `CLIClient` fake and the design fixtures: `diff` into packages
/// and files with the board's counts, find, flagged lines, review-only, nothing to update, a failed fetch, and
/// Update through `SheetRun` (success closes, failure and Cancel keep the sheet).
@Suite @MainActor struct ReviewStoreTests {
    let client = FakeCLIClient()
    let scope = Scope.project(URL(fileURLWithPath: "/tmp/review-tests"))
    let pdfDiffText = DesignFixtures.text("diff.pdf", "txt")
    let allDiffText = DesignFixtures.text("diff.pdf", "txt") + DesignFixtures.text("diff.review-pr", "txt")

    func scopeStore(_ snapshot: ScopeSnapshot = DesignFixtures.api) -> ScopeStore {
        let store = ScopeStore(scope: scope, client: client, capabilities: Capabilities(version: Capabilities.minimum))
        store.preload(snapshot: snapshot)
        return store
    }

    func scriptRefresh() async {
        await client.json(.status, in: scope, ScopeStoreTests.status([("pdf", "1.4.0")]))
        await client.json(.audit, in: scope, ScopeStoreTests.emptyAudit)
        await client.json(.doctor(fix: false), in: scope, ScopeStoreTests.cleanDoctor)
    }

    static let pdfFindings: [String: [AuditDocument.Finding]] = {
        let json = """
            [{"rule": "risky-pattern", "path": ".skillcask/skills/pdf/SKILL.md", "line": 12, "message": "curl"},
             {"rule": "invisible-character", "path": ".skillcask/skills/pdf/SKILL.md", "line": 13, "message": "U+202E"}]
            """
        let findings = (try? JSONDecoder().decode([AuditDocument.Finding].self, from: Data(json.utf8))) ?? []
        return ["anthropics/skills": findings]
    }()

    // MARK: - Load and parse

    @Test func loadsTheDiffOfTheSkillsPackageWithTheBoardsCounts() async throws {
        await client.json(.diff(package: "anthropics/skills"), in: scope, pdfDiffText)
        let review = ReviewStore(package: "pdf", offeredVersion: "1.4.0", store: scopeStore())
        #expect(review.package == "anthropics/skills", "a skill id is resolved to its package for diff and update")
        #expect(review.phase == .loading && review.displayName == "pdf")
        #expect(
            ReviewStore(package: "anthropics/skills", store: scopeStore()).displayName == "pdf",
            "the row with the update")
        await review.load()
        #expect(await client.commands == [.diff(package: "anthropics/skills")])
        #expect(review.phase == .loaded && !review.isUpToDate)
        let package = try #require(review.packages.first)
        #expect(package.from == "1.2.0" && package.to == "1.4.0" && package.files.count == 5)
        #expect(ReviewStore.countedFiles(package).count == 4, "the board's 4 files leave out the binary")
        #expect(ReviewStore.totals(package) == (31, 9), "+31 −9 leave out the removed LEGACY.md")
        let counts = package.files.map { ReviewStore.listCounts($0).map { [$0.additions, $0.deletions] } }
        #expect(counts == [[14, 3], [17, 0], [0, 6], nil, nil])
        #expect(
            package.files.map(\.pathInSkill) == [
                "SKILL.md", "scripts/ocr.py", "scripts/fill_form.py", "LEGACY.md", "assets/sample.pdf",
            ])
        #expect(review.selection == ReviewStore.FileID(package: "anthropics/skills", path: "pdf/SKILL.md"))
        #expect(review.lockedElsewhere == nil)
        #expect(review.runTitle == "Updating pdf to 1.4.0…" && review.outcomeText == "Updated pdf to 1.4.0")
        #expect(review.titleWords == "Update pdf" && review.versions == "1.2.0 → 1.4.0")
        #expect(review.subtitle == "anthropics/skills · GitHub · 4 files · +31 −9")
        #expect(
            review.footnote
                == "Updating writes the new version to skills.lock and relinks pdf for Claude Code and Cursor. "
                + "You can cancel while it runs.")
    }

    @Test func updateAllReadsEveryPackageAndUpdatesWhatItShowed() async {
        await client.json(.diff(package: nil), in: scope, allDiffText)
        let review = ReviewStore(package: nil, store: scopeStore())
        await review.load()
        #expect(review.isAll && review.packages.map(\.name) == ["anthropics/skills", "acme/review-pr"])
        #expect(review.packages.map { review.name(of: $0.name) } == ["pdf", "review-pr"])
        #expect(review.packages.map { ReviewStore.countedFiles($0).count } == [4, 3])
        #expect(ReviewStore.totals(review.packages[1]) == (12, 2))
        #expect(review.updateCommand == .update(packages: ["anthropics/skills", "acme/review-pr"]))
        #expect(review.runTitle == "Updating 2 packages…" && review.outcomeText == "Updated pdf and review-pr")
        #expect(review.waiting.map(\.skills) == [["jira-syntax", "jira-communication"]])
        #expect(review.waiting.map(\.version) == ["4.3.0"])
        #expect(
            ReviewUpdateCopy.updateAllSubtitle(scope: "api", names: ["pdf", "review-pr"], files: 7)
                == "api · pdf, review-pr · 7 files")
        #expect(
            ReviewUpdateCopy.sectionSummary(files: 4, additions: 31, deletions: 9, flagged: 2)
                == "4 files · +31 −9 · 2 flagged lines")
    }

    @Test func nothingToUpdateIsItsOwnState() async {
        await client.json(.diff(package: "anthropics/skills"), in: scope, DesignFixtures.text("diff.up-to-date", "txt"))
        let review = ReviewStore(package: "anthropics/skills", store: scopeStore())
        await review.load()
        #expect(review.isUpToDate && review.packages.isEmpty && review.selection == nil)
        let run = SheetRun()
        #expect(review.update(with: run, in: scopeStore(), runner: ActionRunner(queue: MutationQueue())) {} == nil)
        #expect(run.phase == .idle)
        #expect(
            ReviewUpdateCopy.upToDateBody(name: "pdf", version: "1.4.0", range: "^1.2")
                == "1.4.0 is installed and matches skills.lock. Nothing newer exists inside your range `^1.2`.")
    }

    @Test func aFailedFetchKeepsTheMessageAndRetryLoadsAgain() async {
        await client.script(
            .diff(package: "anthropics/skills"), in: scope,
            .error(.failed(code: .network, message: "github.com did not answer.", hint: nil, stderr: "")))
        await client.json(.diff(package: "anthropics/skills"), in: scope, pdfDiffText)
        let review = ReviewStore(package: "anthropics/skills", store: scopeStore())
        await review.load()
        guard case .failed(let message) = review.phase else {
            Issue.record("expected a failure, got \(review.phase)")
            return
        }
        #expect(message.title == "github.com did not answer." && message.remedy == .retry)
        #expect(message.action == ErrorCopy.networkAction)
        let attempt = review.attempt
        review.retry()
        #expect(review.phase == .loading && review.attempt == attempt + 1)
        await review.load()
        #expect(review.phase == .loaded && review.packages.count == 1)
    }

    @Test func aCancelledLoadRecordsNothing() async {
        let gate = Gate()
        await client.json(.diff(package: "anthropics/skills"), in: scope, pdfDiffText, gate: gate)
        let review = ReviewStore(package: "anthropics/skills", store: scopeStore())
        let load = Task { await review.load() }
        await gate.arrived()
        load.cancel()
        await gate.open()
        await load.value
        #expect(review.phase == .loading && review.diff == nil && review.error == nil)
    }

    // MARK: - Find and flags

    @Test func findMatchesAcrossFilesAndWraps() {
        let review = ReviewStore(package: "anthropics/skills", store: scopeStore())
        review.preload(DesignFixtures.pdfDiff)
        review.query = "PDFTOTEXT"
        let matches = review.matches
        #expect(matches.count == 3, "case-insensitive, three lines of SKILL.md")
        #expect(review.matchIndex == 0 && review.focus?.line == matches[0])
        review.previousMatch()
        #expect(review.matchIndex == matches.count - 1)
        review.nextMatch()
        #expect(review.matchIndex == 0 && review.selection == matches[0].file)
        review.query = "ocrmypdf"
        #expect(review.matches.count == 1 && review.selection?.path == "pdf/scripts/ocr.py")
        #expect(review.currentMatchInSelection == review.matches[0].line)
        review.query = "no such text"
        #expect(review.matches.isEmpty && review.matchIndex == nil)
    }

    /// Q11 interim: the current audit describes the installed version (old line numbers), so a pending update
    /// shows no flags even when that audit has findings on line numbers the new version also has.
    @Test func aPendingUpdateShowsNoFlagsFromTheCurrentAudit() async throws {
        let status = #"""
            {"ok":true,"entries":[{"package":"anthropics/skills","skill":"pdf","version":"1.2.0","state":"ok",
              "ok":true}],"policy":{},"repositories":[]}
            """#
        let audit = #"""
            {"ok":false,"skills":[{"skill":"pdf","kind":"package","path":".skillcask/skills/pdf",
              "package":"anthropics/skills","version":"1.2.0","commands":[],"network":[],"paths":[],"env":[],
              "scripts":[],"findings":[
                {"rule":"risky-pattern","path":".skillcask/skills/pdf/SKILL.md","line":12,"message":"curl"},
                {"rule":"invisible-character","path":".skillcask/skills/pdf/SKILL.md","line":13,"message":"U+202E"}]}]}
            """#
        let snapshot = ScopeSnapshot(
            status: try JSONDecoder().decode(StatusDocument.self, from: Data(status.utf8)),
            audit: try JSONDecoder().decode(AuditDocument.self, from: Data(audit.utf8)), doctor: nil, outdated: nil)
        #expect(snapshot.entries.first?.findings.count == 2, "the installed version has findings on lines 12, 13")
        await client.json(.diff(package: "anthropics/skills"), in: scope, pdfDiffText)
        let review = ReviewStore(package: "anthropics/skills", store: scopeStore(snapshot))
        await review.load()
        let package = try #require(review.packages.first)
        #expect(review.flaggedLines.isEmpty && review.flagCounts == (0, 0) && review.flagsByFile.isEmpty)
        #expect(package.files.allSatisfy { review.flags(for: $0, in: package.name).isEmpty }, "no amber dot")
        #expect(!review.hasNewVersionFindings)
        review.nextFlaggedLine()
        #expect(review.focus == nil)
        #expect(
            ReviewUpdateCopy.sectionSummary(files: 4, additions: 31, deletions: 9, flagged: nil)
                == "4 files · +31 −9", "no \"no flagged lines\" claim without a new-version audit")
    }

    /// The planned capability: findings of the NEW version outline their lines and the callout walks them.
    @Test func newVersionFindingsAreFlaggedAndNextFlaggedWalksThem() throws {
        let review = ReviewStore(package: "anthropics/skills", store: scopeStore())
        review.preload(DesignFixtures.pdfDiff, newVersionFindings: Self.pdfFindings)
        let flagged = review.flaggedLines
        #expect(flagged.count == 2 && flagged.allSatisfy { $0.file.path == "pdf/SKILL.md" })
        #expect(review.flagCounts == (1, 1))
        let package = try #require(review.packages.first)
        #expect(review.flaggedCount(of: package) == 2)
        review.selection = ReviewStore.FileID(package: package.name, path: "pdf/LEGACY.md")
        review.nextFlaggedLine()
        #expect(review.focus?.line == flagged[0] && review.selection == flagged[0].file)
        review.nextFlaggedLine()
        #expect(review.focus?.line == flagged[1])
        review.nextFlaggedLine()
        #expect(review.focus?.line == flagged[0], "wraps to the first")
        #expect(
            ReviewUpdateCopy.flagsCallout(risky: 1, invisible: 1)
                == "The new version has 1 risky pattern and 1 invisible character; the flagged lines are outlined "
                + "below.")
    }

    // MARK: - Review-only

    @Test func aMovedTagIsReviewOnlyAndUpdateIsNotTheDefault() {
        let normal = ReviewStore(package: "anthropics/skills", store: scopeStore())
        #expect(normal.updateIsDefault && !normal.isReviewOnly)
        let asked = ReviewStore(package: "anthropics/skills", reviewOnly: true, store: scopeStore())
        #expect(!asked.updateIsDefault)
        let moved = ReviewStore(package: "juliusbrussee/caveman", store: scopeStore(DesignFixtures.apiTagMoved))
        #expect(moved.tagMove?.tag == "v4.1.0" && moved.isReviewOnly && !moved.updateIsDefault)
    }

    /// The footer's primary button as the sheet draws it (`ReviewUpdateSheet.primaryButton` switches on this):
    /// review-only never makes Update the default (Return) action.
    @Test func thePrimaryButtonIsNeverTheDefaultUpdateWhenReviewOnly() async {
        let normal = ReviewStore(package: "anthropics/skills", store: scopeStore())
        #expect(normal.primaryButton(isRunning: false) == .update(isDefault: true, isEnabled: false), "loading")
        normal.preload(DesignFixtures.pdfDiff)
        #expect(normal.primaryButton(isRunning: false) == .update(isDefault: true, isEnabled: true))
        #expect(normal.primaryButton(isRunning: true) == .update(isDefault: true, isEnabled: false))
        let reviewOnly = ReviewStore(package: "anthropics/skills", reviewOnly: true, store: scopeStore())
        reviewOnly.preload(DesignFixtures.pdfDiff)
        #expect(reviewOnly.primaryButton(isRunning: false) == .update(isDefault: false, isEnabled: true))
        let moved = ReviewStore(package: "juliusbrussee/caveman", store: scopeStore(DesignFixtures.apiTagMoved))
        moved.preload(DesignFixtures.pdfDiff)
        #expect(moved.primaryButton(isRunning: false) == .update(isDefault: false, isEnabled: true))
        let upToDate = ReviewStore(package: "anthropics/skills", store: scopeStore())
        upToDate.preload(DesignFixtures.upToDateDiff)
        #expect(upToDate.primaryButton(isRunning: false) == .done)
        let failed = ReviewStore(package: "anthropics/skills", store: scopeStore())
        failed.preload(failure: .failed(code: .network, message: "github.com did not answer.", hint: nil, stderr: "x"))
        #expect(failed.primaryButton(isRunning: false) == .retry)
        if case .failed(let message) = failed.phase {
            #expect(message.details != nil, "stderr gives the fetch-failed state its Details link")
        }
    }

    @Test func aVersionUpdateDoesNotReachIsSaid() {
        let review = ReviewStore(package: "anthropics/skills", offeredVersion: "2.0.0", store: scopeStore())
        review.preload(DesignFixtures.pdfDiff)
        #expect(review.lockedElsewhere?.locks == "1.4.0" && review.lockedElsewhere?.offered == "2.0.0")
    }

    // MARK: - Update

    @Test(.timeLimit(.minutes(1))) func updateRunsUpdateForThePackageAndClosesOnSuccess() async {
        await client.lines(.update(packages: ["anthropics/skills"]), in: scope, ["updated anthropics/skills"])
        await scriptRefresh()
        let store = scopeStore()
        let review = ReviewStore(package: "pdf", store: store)
        review.preload(DesignFixtures.pdfDiff)
        let runner = ActionRunner(queue: MutationQueue())
        let run = SheetRun()
        var closed = false
        let task = review.update(with: run, in: store, runner: runner) { closed = true }
        await task?.value
        #expect(await client.commands.first == .update(packages: ["anthropics/skills"]))
        #expect(closed && run.phase == .succeeded)
        #expect(runner.toast?.text == "Updated pdf to 1.4.0")
    }

    @Test(.timeLimit(.minutes(1))) func updateAllIsOneCall() async {
        let update = Invocation.Command.update(packages: ["anthropics/skills", "acme/review-pr"])
        await client.lines(update, in: scope, [])
        await scriptRefresh()
        let store = scopeStore()
        let review = ReviewStore(package: nil, store: store)
        review.preload(DesignFixtures.updateAllDiff)
        let runner = ActionRunner(queue: MutationQueue())
        let task = review.update(with: SheetRun(), in: store, runner: runner) {}
        await task?.value
        let updates = await client.commands.filter {
            if case .update = $0 { true } else { false }
        }
        #expect(updates == [update])
    }

    @Test(.timeLimit(.minutes(1))) func aFailedUpdateKeepsTheSheetOpenWithTheCLIsHint() async {
        await client.script(
            .update(packages: ["anthropics/skills"]), in: scope,
            .error(
                .failed(
                    code: .problem, message: "anthropics/skills is not in skills.toml", hint: "run skillcask update",
                    stderr: "")))
        await scriptRefresh()
        let store = scopeStore()
        let review = ReviewStore(package: "anthropics/skills", store: store)
        review.preload(DesignFixtures.pdfDiff)
        let runner = ActionRunner(queue: MutationQueue())
        let run = SheetRun()
        var closed = false
        await review.update(with: run, in: store, runner: runner) { closed = true }?.value
        #expect(!closed && run.canClose)
        #expect(run.failure?.reason == "anthropics/skills is not in skills.toml.")
        #expect(run.failure?.action == "Update the skills in this project.")
        #expect(runner.banner == nil, "the sheet shows the failure, not the window")
        let shown = run.failure
        #expect(shown?.title == "Couldn’t update pdf.", "the banner's title, not \"Couldn’t Updating pdf…\"")
        #expect(shown?.reason == "anthropics/skills is not in skills.toml." && shown?.action == run.failure?.action)
    }

    @Test(.timeLimit(.minutes(1))) func cancelStopsTheUpdateAndKeepsTheSheet() async {
        let gate = Gate()
        await client.lines(.update(packages: ["anthropics/skills"]), in: scope, [], gate: gate)
        await scriptRefresh()
        let store = scopeStore()
        let review = ReviewStore(package: "anthropics/skills", store: store)
        review.preload(DesignFixtures.pdfDiff)
        let runner = ActionRunner(queue: MutationQueue())
        let run = SheetRun()
        var closed = false
        let task = review.update(with: run, in: store, runner: runner) { closed = true }
        await gate.arrived()
        #expect(run.isRunning && !run.canClose && run.action?.title == "Updating pdf to 1.4.0…")
        run.cancel()
        await gate.open()
        await task?.value
        #expect(!closed && run.failure?.reason == ErrorCopy.cancelled && run.canClose)
    }

    // MARK: - Copy

    @Test func headerAndFooterWords() {
        #expect(
            ReviewUpdateCopy.subtitle(
                package: "anthropics/skills", source: "GitHub", files: 4, additions: 31, deletions: 9)
                == "anthropics/skills · GitHub · 4 files · +31 −9")
        #expect(
            ReviewUpdateCopy.footer(name: "pdf", agents: ["Claude Code", "Cursor"])
                == "Updating writes the new version to skills.lock and relinks pdf for Claude Code and Cursor. "
                + "You can cancel while it runs.")
        #expect(
            ReviewUpdateCopy.notIncluded(["jira-syntax", "jira-communication"], version: "4.3.0")
                == "jira-syntax and jira-communication are not included: 4.3.0 is still inside the minimum "
                + "release age.")
        #expect(ReviewUpdateCopy.fetchFailed(version: "1.4.0", name: "pdf") == "Couldn’t fetch the changes for 1.4.0")
        #expect(ReviewUpdateCopy.updateAllTitle(count: 2) == "Update 2 packages")
        #expect(
            ReviewProgress.elapsed(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 4.6)) == "0:04"
        )
    }
}
