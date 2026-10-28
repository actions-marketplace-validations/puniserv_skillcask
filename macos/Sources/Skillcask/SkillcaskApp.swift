import SkillcaskUI
import SwiftUI

/// `@main` only (ADR §2): builds the stores once (`Boot.current()`: the live binary, or the design fixtures when
/// `SKILLCASK_UI_FIXTURES=1`), injects them, and declares the window, the Settings window and the menu bar.
@main
struct SkillcaskApp: App {
    @State private var stores = Boot.current()

    var body: some Scene {
        WindowGroup(id: MainWindow.sceneID) {
            MainWindow()
                .skillcaskEnvironment(
                    app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
        }
        .commands { SkillcaskCommands() }
        // S14: the system Settings window, ⌘, from the app menu.
        Settings {
            SettingsView()
                .skillcaskEnvironment(
                    app: stores.app, runner: stores.runner, settings: stores.settings, client: stores.client)
        }
    }
}
