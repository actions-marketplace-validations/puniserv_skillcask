import AppKit
import Foundation
import SkillcaskCore
import SkillcaskDomain
import SwiftUI
import Testing
import Vision

@testable import SkillcaskUI

/// The Activity drawer as AppKit draws it, in an offscreen window: an open drawer over several Checks in a row must
/// not keep a row of a run that ended ("Checking… running", its timer ticking). A run's `ActivityEntry` takes the
/// running row's id in the same main-actor turn that clears `current`; the drawer's `LazyVStack` must not reuse the
/// running cell for it.
@Suite(.serialized) @MainActor struct ActivityDrawerHostTests {
    let client = FakeCLIClient()
    let scope = Scope.project(URL(fileURLWithPath: "/tmp/drawer"))
    let capabilities = Capabilities(version: Capabilities.minimum)

    /// The words drawn in `view`, read back from its pixels (the hosting view's accessibility tree stays empty
    /// in a test process without an assistive client).
    static func texts(in view: NSView) -> [String] {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return [] }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let image = bitmap.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    /// One run-loop turn, then layout and drawing.
    static func settle(_ window: NSWindow, _ host: NSView) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        host.display()
    }

    @Test(.timeLimit(.minutes(1))) func endedChecksLeaveNoRunningRowInAnOpenDrawer() async {
        _ = NSApplication.shared
        let stores = Boot.fixtures()
        let runner = ActionRunner(queue: MutationQueue())
        let store = ScopeStore(scope: scope, client: client, capabilities: capabilities) { _ in SkillText.parse("") }
        store.preload(snapshot: DesignFixtures.api)
        runner.preloadActivity([], shown: true)

        let host = NSHostingView(
            rootView: ActivityDrawer().environment(runner).environment(stores.app)
                .frame(width: Size.listWidth, height: 400))
        host.frame = NSRect(x: 0, y: 0, width: Size.listWidth, height: 400)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        // Closed by this test, released by ARC: AppKit's release on close would free it a second time.
        window.isReleasedWhenClosed = false
        defer { window.close() }
        Self.settle(window, host)

        for _ in 0..<3 {
            let gate = Gate()
            await client.json(.doctor(fix: false), in: scope, ScopeStoreTests.cleanDoctor, gate: gate)
            let task = Task { await runner.check(in: store) }
            await gate.arrived()
            Self.settle(window, host)
            let inFlight = Self.texts(in: host)
            #expect(inFlight.contains { $0.contains(ActivityCopy.running) }, "the run in flight shows: \(inFlight)")
            await gate.open()
            await task.value
            Self.settle(window, host)
        }

        #expect(runner.current == nil)
        #expect(runner.activity.count == 3)
        let texts = Self.texts(in: host)
        let ghosts = texts.filter { $0.contains(ActivityCopy.running) }
        #expect(ghosts.isEmpty, "rows of runs that ended still read running: \(ghosts)\nall: \(texts)")
        let checked = texts.filter { $0.contains(ActionCopy.checked(ShellCopy.name(of: scope))) }
        #expect(checked.count == 3, "each ended Check has its own row: \(texts)")
    }
}

/// The drawer's row identities, without drawing: a run's finished entry never takes its running row's identity.
@Suite @MainActor struct ActivityDrawerItemTests {
    static func entry(id: UUID = UUID(), startedAt: Date = Date()) -> ActionRunner.ActivityEntry {
        ActionRunner.ActivityEntry(
            id: id, title: ActionCopy.checking, headline: "Checked My Skills", command: "skillcask -g doctor --json",
            scope: .personal, startedAt: startedAt, duration: .zero, status: .exited(0), error: nil, transcript: [],
            isMutation: false, expectsDocument: true)
    }

    @Test func aRunningRowAndItsFinishedEntryHaveDifferentIdentities() throws {
        let runner = ActionRunner(queue: MutationQueue())
        runner.preloadRunning(title: ActionCopy.checking, in: .personal)
        let running = try #require(runner.current)
        let before = ActivityDrawer.items(current: running, activity: [])
        let after = ActivityDrawer.items(current: nil, activity: [Self.entry(id: running.id)])
        #expect(before.map(\.id) == [.running(running.id)])
        #expect(after.map(\.id) == [.finished(running.id)])
        #expect(Set(before.map(\.id)).isDisjoint(with: after.map(\.id)))
    }

    @Test func theRunInFlightComesFirstAndEveryIdentityIsUnique() throws {
        let runner = ActionRunner(queue: MutationQueue())
        runner.preloadRunning(title: ActionCopy.checking, in: .personal)
        let running = try #require(runner.current)
        let entries = (0..<3).map { _ in Self.entry() }
        let items = ActivityDrawer.items(current: running, activity: entries)
        #expect(items.map(\.id) == [.running(running.id)] + entries.map { .finished($0.id) })
        #expect(Set(items.map(\.id)).count == items.count)
    }
}
