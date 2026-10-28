import SwiftUI

/// The Settings window (S14), opened with ⌘, from the app's `Settings` scene: toolbar tabs General, Search,
/// Updates and Advanced (Settings and Settings-States boards), and Global (no board: `-g config`, D48), each a
/// `SettingsPane` at the board's 600 pt width.
public struct SettingsView: View {
    /// The tabs, in toolbar order.
    public enum Tab: String, CaseIterable, Hashable, Sendable {
        case general
        case search
        case updates
        case global
        case advanced

        var title: String {
            switch self {
            case .general: SettingsCopy.general
            case .search: SettingsCopy.search
            case .updates: SettingsCopy.updates
            case .global: SettingsCopy.global
            case .advanced: SettingsCopy.advanced
            }
        }

        /// The board's toolbar glyphs: a gear, a magnifier, a circled down arrow, a terminal prompt; Global's
        /// sliders are not on a board.
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .search: "magnifyingglass"
            case .updates: "arrow.down.circle"
            case .global: "slider.horizontal.3"
            case .advanced: "terminal"
            }
        }
    }

    @State private var tab: Tab

    public init(tab: Tab = .general) {
        _tab = State(initialValue: tab)
    }

    public var body: some View {
        TabView(selection: $tab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Self.pane(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .frame(width: Size.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder static func pane(_ tab: Tab) -> some View {
        switch tab {
        case .general: GeneralPane()
        case .search: SearchPane()
        case .updates: UpdatesPane()
        case .global: GlobalPane()
        case .advanced: AdvancedPane()
        }
    }
}
