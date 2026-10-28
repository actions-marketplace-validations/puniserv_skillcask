import Foundation
import SkillcaskCore
import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// The Activity board's list column (360 × 748: the board's window less its 52 pt toolbar) over the api
    /// scope. `closed`: the list alone, as at launch; `open`: the board's six rows as production records them,
    /// collapsed; `expanded`: the board's state, the newest run's transcript open; `failed`: the Sync that needed a
    /// sign-in expanded, with the environment names the run got; `readExpanded`: opening api expanded through
    /// Details (`detailsRequest`), so the drawer scrolls to it, its three commands; `running`: a Sync in flight on top, expanded; `empty`: the drawer before any
    /// run this session.
    static let activity: [Entry] = ActivitySample.Variant.allCases.map { variant in
        Entry(id: "P3-14", state: variant.rawValue, size: ActivitySample.size) {
            AnyView(ActivitySample(variant))
        }
    }
}

/// The list column with the drawer over a fresh fixture boot, so light and dark never share a store.
private struct ActivitySample: View {
    enum Variant: String, CaseIterable {
        case closed, open, expanded, failed, readExpanded, running, empty
    }

    nonisolated static let size = CGSize(width: Size.listWidth, height: 748)

    @State private var stores: Boot.Stores

    @MainActor init(_ variant: Variant) {
        let stores = Boot.fixtures(selecting: Boot.apiScope, selection: "pdf")
        Self.configure(variant, runner: stores.runner)
        _stores = State(initialValue: stores)
    }

    @MainActor private static func configure(_ variant: Variant, runner: ActionRunner) {
        let entries = boardEntries
        switch variant {
        case .closed:
            runner.preloadActivity(entries, shown: false)
        case .open:
            runner.preloadActivity(entries)
        case .expanded:
            runner.preloadActivity(entries, expanded: [entries[0].id])
        case .failed:
            runner.preloadActivity(entries, expanded: [entries[2].id])
        case .readExpanded:
            // Through Details, as the app opens a row: expanded and scrolled to.
            runner.preloadActivity(entries, shown: false)
            runner.showDetails(of: entries[5].id)
        case .running:
            runner.preloadActivity(entries)
            runner.preloadRunning(
                title: ActionCopy.syncing, in: Boot.apiScope, startedAt: Date(timeIntervalSinceNow: -3.2),
                lines: [.stdout("Installing jira-syntax v4.2.0 (packagist)…"), .stdout("Verifying content hash… ok")],
                command: "skillcask install")
            if let id = runner.current?.id {
                runner.toggleExpanded(id)
            }
        case .empty:
            runner.preloadActivity([])
        }
    }

    /// The board's six rows as production records them, at the board's clock times (today, on this Mac) and
    /// durations (`DesignFixtures.activity`). Titles and commands come from the app's own Copy and `Invocation`,
    /// not the board's sketch: the update has no `--json` at 0.9.4, and a window Sync fails as "Couldn’t sync"
    /// (the scope is the window's). Two runs (the update in its sheet, Sync and Check from the toolbar) and three
    /// reads the user started (Review Update's `diff`, Check for updates, opening api). The failed Sync carries
    /// the CLI's two stderr lines and the proxy name Settings gave it.
    @MainActor private static var boardEntries: [ActionRunner.ActivityEntry] {
        let board = DesignFixtures.activity
        func at(_ index: Int) -> (start: Date, duration: Duration, end: Date) {
            let start = today(at: board[index].startedAt)
            let seconds = board[index].seconds
            return (start, .milliseconds(Int(seconds * 1000)), start.addingTimeInterval(seconds))
        }
        func trace(_ command: Invocation.Command, status: Int32 = 0) -> ActionRunner.ReadTrace {
            ActionRunner.ReadTrace(command: commandLine(command), status: .exited(status))
        }
        let api = ShellCopy.name(of: Boot.apiScope)
        let banner = DesignFixtures.signInBanner
        var signIn: [OutputLine] = []
        if case .failed(_, let message, let hint, _) = banner.error {
            signIn = [.stderr("error: \(message)")] + (hint.map { [.stderr("hint: \($0)")] } ?? [])
        }
        return [
            ActionRunner.ActivityEntry(
                title: ReviewUpdateCopy.updating("pdf", to: "1.4.0"), headline: OutcomeCopy.updated("pdf", to: "1.4.0"),
                command: commandLine(.update(packages: ["anthropics/skills"])), scope: Boot.apiScope,
                startedAt: at(0).start, duration: at(0).duration, status: .exited(0), error: nil,
                transcript: DesignFixtures.Transcripts.updatePdf.map(OutputLine.stdout), isMutation: true,
                expectsDocument: false),
            .read(
                headline: ActivityCopy.reviewed("pdf", from: "1.2.0", to: "1.4.0"), failure: "",
                scope: Boot.apiScope, startedAt: at(1).start, traces: [trace(.diff(package: "anthropics/skills"))],
                error: nil, expectsDocument: false, now: at(1).end),
            ActionRunner.ActivityEntry(
                title: ActionCopy.syncing, headline: ActionCopy.couldNotSync,
                command: commandLine(.install(frozen: false)),
                scope: Boot.apiScope, startedAt: at(2).start, duration: at(2).duration, status: .exited(2),
                error: banner.error, transcript: signIn, isMutation: true, expectsDocument: false,
                environmentOverrides: ["HTTPS_PROXY"]),
            ActionRunner.ActivityEntry(
                title: ActionCopy.checking, headline: ActionCopy.checked(api),
                command: commandLine(.doctor(fix: false)), scope: Boot.apiScope, startedAt: at(3).start,
                duration: at(3).duration, status: .exited(0), error: nil, transcript: [], isMutation: false,
                expectsDocument: true),
            .read(
                headline: ActivityCopy.checkedForUpdates, failure: "", scope: Boot.apiScope, startedAt: at(4).start,
                traces: [trace(.outdated)], error: nil, now: at(4).end),
            .read(
                headline: ActivityCopy.opened(api), failure: "", scope: Boot.apiScope, startedAt: at(5).start,
                traces: [trace(.status), trace(.audit), trace(.doctor(fix: false))], error: nil, now: at(5).end),
        ]
    }

    /// The command line production shows for `command` in api.
    private static func commandLine(_ command: Invocation.Command) -> String {
        let capabilities = Capabilities(version: Capabilities.minimum)
        return (try? Invocation(command, in: Boot.apiScope, capabilities: capabilities))?.displayCommand
            ?? ActionCopy.unbuilt
    }

    /// `14:02` today in the Mac's time zone, as the drawer prints it back.
    private static func today(at clock: String) -> Date {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        let calendar = Calendar.current
        guard parts.count == 2,
            let date = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date())
        else { return Date() }
        return date
    }

    var body: some View {
        if let store = stores.app.store(for: Boot.apiScope) {
            ActivityPane {
                SkillListView(store: store)
            }
            .transaction { $0.disablesAnimations = true }
            .skillcaskEnvironment(
                app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
        }
    }
}
