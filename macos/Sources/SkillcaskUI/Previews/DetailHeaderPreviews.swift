import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// The detail header in the Main board's state (pdf, update) and every Detail-States header: project,
    /// dependency, not managed with a known and an unknown source, abandoned, up to date, and offline (pdf from
    /// the offline snapshot, where `outdated` never answered).
    ///
    /// The state line states `status.state` (`DetailHeader.stateHealth`), so `project` and
    /// `notManagedUnknown` read "Project skill" / "Not managed" although their fixtures carry findings.
    /// `projectClean` is my-notes without findings and renders the same line. `notManaged` (caveman in the api
    /// project) is a planned shape: 0.9.4 reports not managed skills in the personal scope only.
    static let detailHeader: [Entry] = [
        Entry(id: "P2-6", state: "update", size: CGSize(width: 600, height: 260)) {
            AnyView(DetailHeaderSample(entry: DesignFixtures.pdf))
        },
        Entry(id: "P2-6", state: "project", size: CGSize(width: 600, height: 200)) {
            AnyView(DetailHeaderSample(entry: DesignFixtures.myNotes))
        },
        Entry(id: "P2-6", state: "projectClean", size: CGSize(width: 600, height: 200)) {
            AnyView(DetailHeaderSample(entry: cleanProject))
        },
        Entry(id: "P2-6", state: "dependency", size: CGSize(width: 600, height: 200)) {
            AnyView(
                DetailHeaderSample(
                    entry: DesignFixtures.safeRefactor,
                    requiredBy: DesignFixtures.api.requirerSkills(of: DesignFixtures.safeRefactor)))
        },
        Entry(id: "P2-6", state: "notManaged", size: CGSize(width: 600, height: 200)) {
            AnyView(DetailHeaderSample(entry: DesignFixtures.caveman))
        },
        Entry(id: "P2-6", state: "notManagedUnknown", size: CGSize(width: 600, height: 200)) {
            AnyView(DetailHeaderSample(entry: DesignFixtures.standupSummary))
        },
        Entry(id: "P2-6", state: "abandoned", size: CGSize(width: 600, height: 200)) {
            AnyView(DetailHeaderSample(entry: DesignFixtures.legacyLint))
        },
        Entry(id: "P2-6", state: "upToDate", size: CGSize(width: 600, height: 200)) {
            AnyView(DetailHeaderSample(entry: DesignFixtures.commitMessage))
        },
        Entry(id: "P2-6", state: "offline", size: CGSize(width: 600, height: 200)) {
            AnyView(
                DetailHeaderSample(entry: DesignFixtures.entry("pdf", in: DesignFixtures.apiOffline), offline: true))
        },
    ]
}

/// my-notes with its audit findings taken away: the Detail-States "Project skill" state line.
private let cleanProject: SkillEntry = {
    let notes = DesignFixtures.myNotes
    return SkillEntry(
        id: notes.id, name: notes.name, kind: notes.kind, source: notes.source, version: notes.version,
        state: notes.state, health: .projectSkill, update: notes.update, findings: [], path: notes.path,
        description: notes.description)
}()

/// One header at detail-column width on the window surface, the Overview tab selected.
private struct DetailHeaderSample: View {
    let entry: SkillEntry
    var offline = false
    var requiredBy: [String]? = nil
    @State private var tab = DetailTab.overview

    var body: some View {
        DetailHeader(entry: entry, isOffline: offline, selectedTab: $tab, requiredBy: requiredBy)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.surfaceWindow)
    }
}
