import SkillcaskCore
import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// P3-3: the detail column (header and Overview tab) at 720 × 800 for the Main board's pdf and every
    /// Detail-States state. Composed from `DetailHeader` and `OverviewTab` over fixture data, as `SkillDetailView`
    /// composes them, so no store task reloads the detail during the render (the offline state keeps no `info`).
    static let detail: [Entry] = [
        entry("update") { DetailSample(entry: DesignFixtures.pdf, info: DesignFixtures.pdfInfo) },
        entry("project") { DetailSample(entry: DesignFixtures.myNotes, info: DesignFixtures.myNotesInfo) },
        entry("dependency") { DetailSample(entry: DesignFixtures.safeRefactor, info: DesignFixtures.safeRefactorInfo) },
        entry("notManaged") { DetailSample(entry: DesignFixtures.caveman, info: nil) },
        entry("notManagedUnknown") {
            DetailSample(
                entry: DesignFixtures.standupSummary, info: nil, snapshot: DesignFixtures.personal, scope: .personal)
        },
        entry("abandoned") { DetailSample(entry: DesignFixtures.legacyLint, info: DesignFixtures.legacyLintInfo) },
        entry("offline") {
            DetailSample(
                entry: DesignFixtures.commitMessageOffline, info: nil, snapshot: DesignFixtures.apiOffline,
                offline: true)
        },
    ]

    private static func entry(_ state: String, _ make: @escaping @MainActor @Sendable () -> DetailSample) -> Entry {
        Entry(id: "P3-3", state: state, size: CGSize(width: 720, height: 800)) { AnyView(make()) }
    }
}

/// One detail column over fixture data: the header with the Overview tab selected and the tab's body.
private struct DetailSample: View {
    let entry: SkillEntry
    let info: InfoDocument?
    var snapshot = DesignFixtures.api
    var scope = Boot.apiScope
    var offline = false
    @State private var tab = DetailTab.overview

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(
                entry: entry, isOffline: offline, selectedTab: $tab, requiredBy: snapshot.requirerSkills(of: entry),
                allowedRange: info.flatMap { DetailOverviewCopy.allowedRange(why: $0.why) })
            OverviewTab(
                content: OverviewContent(
                    entry: entry, detail: detail, snapshot: snapshot, scope: scope, isOffline: offline),
                checkedAt: snapshot.checkedAt)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surfaceWindow)
    }

    private var detail: SkillDetail {
        offline
            ? SkillDetail(
                infoError: .failed(code: .network, message: "github.com did not answer.", hint: nil, stderr: ""))
            : SkillDetail(info: info)
    }
}
