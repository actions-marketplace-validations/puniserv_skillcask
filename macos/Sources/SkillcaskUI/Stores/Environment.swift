import SkillcaskCore
import SwiftUI

extension EnvironmentValues {
    /// The CLI seam for views that need it directly (previews swap a fake); stores get theirs by init. The default
    /// is one stored instance: an inline class allocation would be re-created on every access.
    @Entry public var cliClient: any CLIClient = UnavailableCLIClient.shared
}

/// The `CLIClient` of a view tree that was given none: every call fails as a missing binary, so a forgotten
/// `.skillcaskEnvironment` shows the onboarding state rather than crashing.
public struct UnavailableCLIClient: CLIClient {
    public static let shared = UnavailableCLIClient()

    /// Always `CLIError.binaryMissing`.
    public func run(
        _ invocation: Invocation, onLine: @escaping @Sendable (OutputLine) -> Void
    ) async throws(CLIError) -> RunResult {
        throw .binaryMissing(searched: [])
    }
}

extension View {
    /// Injects the three app-lifetime stores and the CLI seam at the root of a scene: views read them with
    /// `@Environment(AppStore.self)`, `@Environment(ActionRunner.self)`, `@Environment(SettingsStore.self)`.
    public func skillcaskEnvironment(
        app: AppStore, runner: ActionRunner, settings: SettingsStore, client: any CLIClient
    ) -> some View {
        environment(app)
            .environment(runner)
            .environment(settings)
            .environment(\.cliClient, client)
    }
}
