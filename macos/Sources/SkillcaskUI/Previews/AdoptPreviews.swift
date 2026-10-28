import SkillcaskCore
import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// The Adopt sheet at `Size.adoptSheet` over the personal fixture scope (12 not managed skills, 9 with a
    /// recorded source), one state per Adopt-States panel plus the states the board leaves out: `known` (caveman,
    /// the locked recorded source), `knownChanged` (after Change…), `unknown` (standup-summary, empty field),
    /// `unknownInvalid` (a typed source that is not one of the three shapes), `singleFailure` (the run failed, the
    /// sheet stays open), `batch` (the checklist, collapsed as the board draws it), `batchExpanded` (after "… 6 more"),
    /// `needsSource` (a "needs a source" row narrowed to, with Back), `batchProgress` (4 of 9 midway), `batchFailed` (a failure stopped
    /// the rest) and `project` (the api project, where the CLI does not adopt; a planned shape: 0.9.1 reports no not
    /// managed row in a project scope, so this sheet is only reachable on a later CLI). The Remove alert is a system alert
    /// and is not rendered; `RemoveTests` pins its words. `singleProgress` ("Adopting caveman…" with the
    /// CLI's lines), `knownLatest` (Latest chosen; `known` shows the CLI's default rule) and `batchDone` (each row's version and "copy kept").
    static let adopt: [Entry] = [
        entry("known") { AdoptSample(skills: ["caveman"]) },
        entry("knownChanged") {
            AdoptSample(skills: ["caveman"], source: "github:juliusbrussee/caveman", editing: true)
        },
        entry("unknown") { AdoptSample(skills: ["standup-summary"]) },
        entry("unknownInvalid") { AdoptSample(skills: ["standup-summary"], source: "github:Standup") },
        entry("singleFailure") {
            AdoptSample(
                skills: ["caveman"], phase: .failed(AdoptSample.networkFailure(AdoptCopy.couldNotAdopt("caveman"))))
        },
        entry("batch") { AdoptSample(skills: AdoptSample.notManaged) },
        entry("batchExpanded") { AdoptSample(skills: AdoptSample.notManaged, showsAll: true) },
        entry("needsSource") { AdoptSample(skills: AdoptSample.notManaged, focused: "standup-summary") },
        entry("batchProgress") {
            AdoptSample(
                skills: AdoptSample.notManaged, phase: .running(title: AdoptCopy.runningBatch(count: 9)),
                items: AdoptSample.midway)
        },
        entry("batchFailed") {
            AdoptSample(
                skills: AdoptSample.notManaged,
                phase: .failed(AdoptSample.networkFailure(AdoptCopy.couldNotAdopt("commit-message"))),
                items: AdoptSample.failed)
        },
        entry("project") { AdoptSample(skills: ["caveman"], scope: Boot.apiScope) },
        // The single run's progress in the sheet, a chosen rule, and a batch that finished.
        entry("singleProgress") {
            AdoptSample(
                skills: ["caveman"], phase: .running(title: AdoptCopy.running("caveman")),
                lines: AdoptSample.adoptLines)
        },
        entry("knownLatest") { AdoptSample(skills: ["caveman"], rule: .latest) },
        entry("batchDone") {
            AdoptSample(skills: AdoptSample.notManaged, phase: .succeeded, items: AdoptSample.done)
        },
    ]

    private static func entry(_ state: String, _ make: @escaping @MainActor @Sendable () -> AdoptSample) -> Entry {
        Entry(id: "P3-10", state: state, size: Size.adoptSheet) { AnyView(make()) }
    }
}

/// The sheet over the fixture stores. A sheet that has not run is drawn through `SheetHost`, as `MainWindow`
/// presents it; one midway is drawn as `AdoptSheet` with a preloaded `SheetRun`, which `SheetHost` cannot pass.
private struct AdoptSample: View {
    let skills: [String]
    var scope: Scope = .personal
    var source = ""
    var editing = false
    var phase: SheetRun.Phase?
    var items: [SheetRun.Item] = []
    var focused: String?
    var showsAll = false
    /// The single run's live lines (`singleProgress`).
    var lines: [String] = []
    var rule: VersionRule?

    /// The not managed rows of the personal fixture, in its order.
    static let notManaged = DesignFixtures.personal.entries.filter(\.isNotManaged).map(\.id)

    /// The batch of the board midway: three done, commit-message running, the rest waiting.
    static let midway: [SheetRun.Item] = [
        SheetRun.Item(id: "caveman", state: .done(.milliseconds(2100)), note: "Adopted 4.0.1 · copy kept"),
        SheetRun.Item(id: "pdf", state: .done(.milliseconds(3400)), note: "Adopted 1.4.0 · copy kept"),
        SheetRun.Item(id: "frontend-design", state: .done(.milliseconds(2800)), note: "Adopted 0.6.0"),
        SheetRun.Item(id: "commit-message", state: .running),
        SheetRun.Item(id: "sql-review", state: .waiting),
        SheetRun.Item(id: "changelog", state: .waiting),
        SheetRun.Item(id: "docx", state: .waiting),
        SheetRun.Item(id: "xlsx", state: .waiting),
        SheetRun.Item(id: "pptx", state: .waiting),
    ]

    /// The same batch after commit-message failed: the rest skipped.
    static let failed: [SheetRun.Item] = midway.map { item in
        switch item.state {
        case .running:
            SheetRun.Item(
                id: item.id,
                state: .failed(networkFailure(AdoptCopy.couldNotAdopt("commit-message")), .milliseconds(5200)))
        case .waiting: SheetRun.Item(id: item.id, state: .skipped)
        default: item
        }
    }

    /// Every row adopted (the sheet would close; drawn as it stood).
    static let done: [SheetRun.Item] = midway.map { item in
        switch item.state {
        case .done: item
        default: SheetRun.Item(id: item.id, state: .done(.milliseconds(2400)), note: "Adopted 1.0.0 · copy kept")
        }
    }

    /// What `add --adopt` prints while it runs, as the single progress shows it.
    static let adoptLines = [
        "adopted ~/.claude/skills/caveman (moved to ~/.config/skillcask/adopted/1761700000/.claude/skills/caveman)",
        #"added juliusbrussee/caveman = "^4.0" (4.0.1)"#,
    ]

    static func networkFailure(_ title: String) -> UserMessage {
        ErrorCopy.message(
            for: .failed(code: .network, message: "repo.packagist.org did not answer.", hint: nil, stderr: ""),
            title: title)
    }

    var body: some View {
        let stores = Boot.fixtures(selecting: scope, selection: nil)
        Group {
            if let store = stores.app.store(for: scope) {
                if let phase {
                    AdoptSheet(
                        skills: skills, store: store, onClose: {}, run: preloaded(phase, runner: stores.runner),
                        startedAt: Date(timeIntervalSinceNow: -21))
                } else if let rule {
                    AdoptSheet(skills: skills, store: store, onClose: {}, rule: rule)
                } else if let focused {
                    AdoptSheet(skills: skills, store: store, onClose: {}, focused: focused)
                } else if showsAll {
                    AdoptSheet(skills: skills, store: store, onClose: {}, showsAll: true)
                } else if source.isEmpty && !editing {
                    SheetHost(sheet: .adopt(skills: skills), store: store, onClose: {})
                } else {
                    AdoptSheet(skills: skills, store: store, onClose: {}, source: source, editing: editing)
                }
            }
        }
        .skillcaskEnvironment(app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
    }

    private func preloaded(_ phase: SheetRun.Phase, runner: ActionRunner) -> SheetRun {
        let run = SheetRun()
        if !lines.isEmpty, case .running(let title) = phase {
            runner.preloadRunning(
                title: title, in: scope, from: .sheet, startedAt: Date(timeIntervalSinceNow: -4),
                lines: lines.map(OutputLine.stdout), command: "skillcask -g add --adopt -- github:juliusbrussee/caveman"
            )
        }
        run.preload(phase: phase, items: items, runner: runner)
        return run
    }
}

#Preview("AdoptSheet known, light") {
    AdoptSample(skills: ["caveman"])
}

#Preview("AdoptSheet batch, dark") {
    AdoptSample(skills: AdoptSample.notManaged)
        .preferredColorScheme(.dark)
}
