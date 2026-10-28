import Foundation
import SkillcaskCore
import SkillcaskDomain

/// Which of the Overview and Overview-States boards the detail column shows for a scope. Pure, so the tests pin it.
enum OverviewState: Hashable {
    /// Overview-States Loading: no status result yet; skeleton cards, toolbar disabled.
    case loading
    /// Overview-States "Folder without skills.toml": the Set Up block.
    case notSetUp
    /// The first load failed and there is nothing to show.
    case failed(CLIError)
    /// Overview-States "No projects yet": My Skills is selected and the sidebar lists no project.
    case noProjects(ScopeSnapshot)
    /// The Overview board (attention) and Overview-States Healthy: the strip and the six cards.
    case ready(ScopeSnapshot)

    /// - Parameters:
    ///   - isSetUp: The sidebar's manifest check (`AppStore.ScopeItem.isSetUp`).
    ///   - isPersonal: The scope is My Skills.
    ///   - hasProjects: The sidebar lists at least one project.
    static func resolve(
        snapshot: ScopeSnapshot?, presentation: Presentation, isSetUp: Bool, isPersonal: Bool, hasProjects: Bool
    ) -> OverviewState {
        if !isSetUp || (snapshot == nil && presentation == .noManifest) {
            return .notSetUp
        }
        if let snapshot {
            return isPersonal && !hasProjects ? .noProjects(snapshot) : .ready(snapshot)
        }
        if case .error(let error) = presentation {
            return .failed(error)
        }
        return .loading
    }

    /// The strip of this state.
    func strip(now: Date = .now) -> OverviewStrip {
        switch self {
        case .loading: .loading
        case .failed: .failed
        case .notSetUp: .notSetUp
        case .noProjects(let snapshot): .ready(snapshot, now: now, showsCheckNow: false)
        case .ready(let snapshot): .ready(snapshot, now: now)
        }
    }
}
