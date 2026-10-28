import SkillcaskCore
import SwiftUI

/// What `MainWindow` shows for `AppStore.presentedSheet`: one destination per `AppStore.Sheet` case, each in its
/// own feature file, over the selected scope's store. `.remove` is never a sheet (it is `RemoveAlert`). A plain
/// view, so the render tool can draw a sheet as a registry entry at its size (`Size.reviewSheet` …) without a
/// presenting window.
struct SheetHost: View {
    let sheet: AppStore.Sheet
    let store: ScopeStore
    let onClose: () -> Void

    var body: some View {
        switch sheet {
        case .update(let package, let target, let reviewOnly):
            ReviewUpdateSheet(
                target: .package(package, version: target, reviewOnly: reviewOnly), store: store, onClose: onClose)
        case .updateAll:
            ReviewUpdateSheet(target: .all, store: store, onClose: onClose)
        case .addSkill(let query):
            AddSkillSheet(query: query, store: store, onClose: onClose)
        case .adopt(let skills):
            AdoptSheet(skills: skills, store: store, onClose: onClose)
        case .remove:
            EmptyView()
        }
    }
}
