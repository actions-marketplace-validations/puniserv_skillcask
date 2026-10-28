import Foundation
import SkillcaskCore

/// Which S13 board the onboarding sheet draws (Onboarding: CLI missing; Onboarding-States: CLI too old). Pure, so
/// the tests pin the mapping from `AppStore.CLIState`.
enum OnboardingState: Hashable {
    /// No usable binary: not found, not executable, or `--version` printed no version.
    case missing
    /// A binary older than `Capabilities.minimum`; `path` is where it was found (nil when unknown).
    case tooOld(found: Version, needs: Version, path: String?)

    /// The state for `cli`, with the located binary for the Found row; nil while locating or once ready, when
    /// the sheet keeps the state it last showed (locating) or closes (ready).
    static func resolve(_ cli: AppStore.CLIState, binary: Locator.Choice?) -> OnboardingState? {
        switch cli {
        case .missing: .missing
        case .tooOld(let found, let needs): .tooOld(found: found, needs: needs, path: binary?.url.path)
        case .locating, .ready: nil
        }
    }

    /// The sheet's title.
    var title: String {
        switch self {
        case .missing: OnboardingCopy.missingTitle
        case .tooOld: OnboardingCopy.tooOldTitle
        }
    }
}
