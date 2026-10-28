import SkillcaskCore
import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// The Running board's list column (380 wide, as its panels) and the Health-States popover (380 wide,
    /// its content; the system popover's chrome is not drawn by a render). `runningDimmed`: a Sync just started,
    /// the bar in the header and the rows at 50 %; `longRun`: the same Sync at 0:03, grown into the block with
    /// Cancel and two output lines; `toast`: the success toast; `failureBanner`: the sign-in banner;
    /// `integrity`: the exit-4 banner beside a success toast; `popoverProblems`, `popoverRepaired`,
    /// `popoverAllPassed` (passed checks expanded, as the board's third panel).
    static let running: [Entry] =
        RunningSample.Variant.allCases.map { variant in
            Entry(id: "P3-11", state: variant.rawValue, size: CGSize(width: RunningSample.width, height: 700)) {
                AnyView(RunningSample(variant))
            }
        } + [
            popover("popoverProblems", DesignFixtures.api),
            popover("popoverRepaired", DesignFixtures.apiRepaired),
            popover("popoverAllPassed", DesignFixtures.website, showsPassed: true),
        ]

    private static func popover(_ state: String, _ snapshot: ScopeSnapshot, showsPassed: Bool = false) -> Entry {
        Entry(id: "P3-11", state: state, size: CGSize(width: HealthPopover.width + 2 * Spacing.l, height: 520)) {
            AnyView(HealthPopoverSample(snapshot: snapshot, showsPassed: showsPassed))
        }
    }
}

/// The list column over a fresh fixture boot, so light and dark never share a store.
private struct RunningSample: View {
    enum Variant: String, CaseIterable {
        case runningDimmed, longRun, toast, failureBanner, integrity
    }

    /// The Running board's `.panel { width: 380px }`.
    nonisolated static let width: CGFloat = 380

    @State private var stores: Boot.Stores

    @MainActor init(_ variant: Variant) {
        let stores = Boot.fixtures(selecting: Boot.apiScope, selection: nil)
        Self.configure(variant, stores: stores)
        _stores = State(initialValue: stores)
    }

    @MainActor private static func configure(_ variant: Variant, stores: Boot.Stores) {
        let runner = stores.runner
        let store = stores.app.store(for: Boot.apiScope)
        switch variant {
        case .runningDimmed:
            runner.preloadRunning(title: ActionCopy.syncing, in: Boot.apiScope)
        case .longRun:
            runner.preloadRunning(
                title: ActionCopy.syncing, in: Boot.apiScope, startedAt: Date(timeIntervalSinceNow: -3.2),
                lines: [
                    .stdout("Installing jira-syntax v4.2.0 (packagist)…"), .stdout("Verifying content hash… ok"),
                ])
        case .toast:
            runner.toast = ToastMessage(text: DesignFixtures.updatedToast.message, emphasis: "pdf")
        case .failureBanner:
            store?.selection = DesignFixtures.sqlReview.id
            let banner = DesignFixtures.signInBanner
            runner.outcome = .banner(ErrorCopy.message(for: banner.error, title: banner.title), id: UUID())
        case .integrity:
            store?.selection = DesignFixtures.reviewPr.id
            let banner = DesignFixtures.integrityBanner
            runner.outcome = .banner(ErrorCopy.message(for: banner.error, title: banner.title), id: UUID())
            // A later success toasts beside the integrity banner, which stays until dismissed.
            runner.outcome = .toast(ToastMessage(text: DesignFixtures.updatedToast.message, emphasis: "pdf"))
        }
    }

    var body: some View {
        if let store = stores.app.store(for: Boot.apiScope) {
            SkillListView(store: store)
                // A render is one frame: the toast is drawn already presented, not mid-way through its insertion.
                .transaction { $0.disablesAnimations = true }
                .skillcaskEnvironment(
                    app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
        }
    }
}

/// The popover's content on the card surface, framed by a hairline where the system popover draws its edge.
private struct HealthPopoverSample: View {
    let snapshot: ScopeSnapshot
    let showsPassed: Bool

    var body: some View {
        if let doctor = snapshot.doctor {
            HealthPopover(
                report: .resolve(doctor),
                when: RunningCopy.when(snapshot.checkedAt, repaired: !doctor.fixed.isEmpty), isBusy: false,
                canSync: ToolbarRules.canSync(snapshot), showsPassed: showsPassed, onRepair: {}, onSync: {},
                onCheckAgain: {}
            )
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(Color.separator, lineWidth: Size.hairline)
            )
            .padding(Spacing.l)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.surfaceGrouped)
        }
    }
}
