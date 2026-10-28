import Foundation

/// The checklist of the Find Projects sheet, from what `projects` found and what the sidebar already lists: every
/// new folder ticked by default (Flow-F1 "chosen ones are added"), the listed ones marked and never added twice.
/// Pure, so the tests pin it.
struct FindProjectsPlan: Hashable {
    /// One folder `projects` found.
    struct Row: Identifiable, Hashable {
        let url: URL
        /// The sidebar already lists it: ticked, disabled, "In the sidebar".
        let isAdded: Bool

        var id: URL { url }
        /// The folder's name, as the sidebar names a project.
        var name: String { AppStore.name(of: url) }
        /// The `~`-abbreviated path.
        var path: String { AppStore.subtitle(of: url) }
    }

    let rows: [Row]

    /// - Parameters:
    ///   - found: The folders in the order `projects` printed them.
    ///   - recents: The sidebar's projects.
    init(found: [URL], recents: [URL]) {
        let listed = Set(recents.map(\.standardizedFileURL))
        var seen = Set<URL>()
        rows = found.map(\.standardizedFileURL).filter { seen.insert($0).inserted }
            .map { Row(url: $0, isAdded: listed.contains($0)) }
    }

    /// Nothing was found: the sheet says so instead of an empty checklist.
    var isEmpty: Bool { rows.isEmpty }

    /// Every folder found is already in the sidebar: nothing to add.
    var isAllAdded: Bool { !rows.isEmpty && rows.allSatisfy(\.isAdded) }

    /// The rows ticked when the sheet opens: every folder not yet in the sidebar.
    var defaultSelection: Set<URL> {
        Set(rows.filter { !$0.isAdded }.map(\.url))
    }

    /// The folders Add adds, in the found order: the ticked ones the sidebar does not list yet.
    func chosen(_ selection: Set<URL>) -> [URL] {
        rows.filter { !$0.isAdded && selection.contains($0.url) }.map(\.url)
    }
}
