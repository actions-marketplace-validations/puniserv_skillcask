import SkillcaskCore
import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// Flow-F4's "Adopt All with Known Sources…" in the list header (My Skills, Not managed chip), and the
    /// toasts that now read the CLI's lines, each a whole sentence over up to two lines with the skill names
    /// semibold: Add (Flow-F2), a long Add that wraps, one Adopt (Flow-F4) and Sync with its count (Flow-F5).
    static let outcomeLines: [Entry] = [
        Entry(id: "P3-17", state: "adoptAllHeader", size: CGSize(width: Size.listWidth, height: 520)) {
            AnyView(AdoptAllHeaderSample())
        },
        toast(
            "addToast",
            OutcomeCopy.added(["jira-syntax", "jira-communication"], version: "4.2.0"),
            emphasis: ["jira-syntax", "jira-communication"]),
        toast(
            "longToast",
            OutcomeCopy.added(
                ["jira-syntax", "jira-communication", "jira-triage", "jira-release-notes"], version: "4.2.0"),
            emphasis: ["jira-syntax", "jira-communication", "jira-triage", "jira-release-notes"]),
        toast("adoptToast", AdoptCopy.adopted("caveman", version: "4.0.1"), emphasis: ["caveman"]),
        toast("syncToast", ActionCopy.synced("api", installed: 1), emphasis: []),
        toast("resolveToast", ActionCopy.resolved("api", installed: 1), emphasis: []),
        // The warning tone: the run ended at exit 0 but did less or other than asked.
        toast("repairLeftToast", ActionCopy.repaired("api", fixed: 1, left: 2), emphasis: [], tone: .warning),
        toast(
            "removeKeptToast",
            RemoveCopy.removedToast(["sql-review"], kept: [], copies: ["pdf"], scope: "api"),
            emphasis: ["sql-review", "pdf"], tone: .warning),
        toast(
            "updateOtherToast",
            ReviewUpdateCopy.updatedOther([pdf], [ReviewUpdateCopy.Locked(pdf, locked: "1.4.1")], single: true),
            emphasis: ["pdf"], tone: .warning),
        toast(
            "updateNotUpdatedToast",
            ReviewUpdateCopy.updatedOther([pdf], [ReviewUpdateCopy.Locked(pdf, locked: nil)], single: true),
            emphasis: ["pdf"], tone: .warning),
    ]

    /// The reviewed package of the update toasts: pdf, 1.2.0 → 1.4.0 (Running board).
    private static let pdf = ReviewUpdateCopy.Reviewed(
        package: "anthropics/skills", name: "pdf", from: "1.2.0", to: "1.4.0")

    private static func toast(
        _ state: String, _ text: String, emphasis: [String], tone: ToastMessage.Tone = .success
    ) -> Entry {
        Entry(id: "P3-17", state: state, size: CGSize(width: Size.listWidth, height: 220)) {
            AnyView(
                Color.surfaceWindow
                    .toast(.constant(ToastMessage(text: text, emphasizing: emphasis, tone: tone)))
                    .transaction { $0.disablesAnimations = true })
        }
    }
}

/// The skills column of My Skills with the Not managed chip active: the batch button under the chips.
private struct AdoptAllHeaderSample: View {
    @State private var stores: Boot.Stores

    @MainActor init() {
        let stores = Boot.fixtures(selecting: .personal, selection: nil)
        stores.app.store(for: .personal)?.filter = .notManaged
        _stores = State(initialValue: stores)
    }

    var body: some View {
        if let store = stores.app.store(for: .personal) {
            SkillListView(store: store)
                .skillcaskEnvironment(
                    app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
        }
    }
}
