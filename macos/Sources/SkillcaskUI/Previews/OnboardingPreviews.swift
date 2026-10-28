import SkillcaskCore
import SwiftUI

extension PreviewRegistry {
    /// The S13 onboarding sheet at its board widths, and the first launch with the CLI fine. `missing` is the
    /// Onboarding board's sheet, `tooOld` the Onboarding-States card (found 0.7.2 at the Homebrew path),
    /// `detecting` the missing sheet while Try Again or Locate… re-detects, `locateRefused` after Locate… was given
    /// a file that is not the tool, `locateTooOld` after it was given the same old copy the sheet found (one copy,
    /// so the strip's version matches Found). `firstLaunch` is the window over
    /// the fixture boot with no project: My Skills selected, its Overview with the not-managed banner, and the
    /// sidebar hint under Projects. The sheet is drawn alone: a window-modal sheet, its scrim and the unified
    /// toolbar are window chrome the offscreen renderer does not draw.
    static let onboarding: [Entry] = [
        sheet("missing", height: Self.missingHeight) { OnboardingSample(state: .missing) },
        sheet("tooOld", height: Self.tooOldHeight, width: 480) { OnboardingSample(state: OnboardingSample.tooOld) },
        sheet("detecting", height: Self.missingHeight) { OnboardingSample(state: .missing, validating: true) },
        sheet("locateRefused", height: Self.missingHeight + Self.stripHeight) {
            OnboardingSample(state: .missing, locateError: .unreadableVersion(output: "usage: sk [-h]"))
        },
        sheet("locateTooOld", height: Self.tooOldHeight + Self.tooOldStripHeight, width: 480) {
            OnboardingSample(
                state: OnboardingSample.tooOld,
                locateError: .tooOld(found: OnboardingSample.tooOldVersion, needs: Capabilities.minimum))
        },
        Entry(id: "P3-12", state: "firstLaunch", size: CGSize(width: 1280, height: 800)) {
            AnyView(FirstLaunchSample())
        },
    ]

    /// Measured content heights (renders), so the footer keeps its 16 pt bottom padding.
    private static let missingHeight: CGFloat = 378
    private static let tooOldHeight: CGFloat = 394
    /// The Locate… strip and its gap: 14 pt between missing steps, 12 between too-old ones.
    private static let stripHeight: CGFloat = 45
    private static let tooOldStripHeight: CGFloat = 43

    private static func sheet(
        _ state: String, height: CGFloat, width: CGFloat = 560,
        _ make: @escaping @MainActor @Sendable () -> OnboardingSample
    ) -> Entry {
        Entry(id: "P3-12", state: state, size: CGSize(width: width, height: height)) { AnyView(make()) }
    }
}

/// The sheet over a fresh fixture boot (the stores only feed the environment; the state is passed in).
private struct OnboardingSample: View {
    let state: OnboardingState
    let locateError: CLIError?
    let validating: Bool
    @State private var stores: Boot.Stores

    @MainActor init(state: OnboardingState, locateError: CLIError? = nil, validating: Bool = false) {
        self.state = state
        self.locateError = locateError
        self.validating = validating
        _stores = State(initialValue: Boot.fixtures(selecting: .personal, selection: nil))
    }

    /// Onboarding-States: 0.7.2 at the Homebrew path, 0.9.1 needed.
    static let tooOldVersion = Version(0, 7, 2)
    static let tooOld = OnboardingState.tooOld(
        found: tooOldVersion, needs: Capabilities.minimum, path: "/opt/homebrew/bin/skillcask")

    var body: some View {
        CLIOnboardingSheet(state: state, locateError: locateError, validating: validating)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.surfaceWindow)
            .skillcaskEnvironment(
                app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
    }
}

/// The window on first launch: no project in the sidebar, My Skills selected with nothing selected in it.
private struct FirstLaunchSample: View {
    @State private var stores: Boot.Stores

    @MainActor init() {
        let stores = Boot.fixtures(selecting: .personal, selection: nil)
        stores.settings.recentProjects = []
        _stores = State(initialValue: stores)
    }

    var body: some View {
        MainWindow()
            .skillcaskEnvironment(
                app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
    }
}

#Preview("CLIOnboardingSheet missing, light") {
    OnboardingSample(state: .missing)
}

#Preview("CLIOnboardingSheet too old, dark") {
    OnboardingSample(state: OnboardingSample.tooOld)
        .preferredColorScheme(.dark)
}
