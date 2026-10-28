import SkillcaskDomain
import SwiftUI

/// The detail's section tabs (Main board "Detail sections"): the system segmented control bound to a
/// `DetailTab`, titles from `DetailCopy`. Height and selection are the system's; the board's 22 pt is
/// `Size.tab` for layout maths only.
///
/// Declared deviation (Q9): the Main board draws an update count badge in the Versions segment ("Versions 1").
/// A system segmented `Picker` cannot host a badge view, and the system control is kept over a custom one; the
/// titles stay the four plain words. The blue strip under the tabs already carries the update, which the
/// designer's note names as "the only place that repeats the Versions tab".
///
/// Which tabs show is `tabs(for:)`: Detail-States draws Overview · Contents · Security only for project, local and
/// not managed skills, which have no lock entry and so no versions.
public struct DetailTabs: View {
    @Binding public var selection: DetailTab
    /// The segments, in board order; `DetailTab.allCases` unless the row hides Versions.
    public let tabs: [DetailTab]

    public init(selection: Binding<DetailTab>, tabs: [DetailTab] = DetailTab.allCases) {
        _selection = selection
        self.tabs = tabs
    }

    /// The tabs of `entry`: all four for a package or dependency, no Versions for a project, local or not managed
    /// skill (Detail-States).
    nonisolated public static func tabs(for entry: SkillEntry) -> [DetailTab] {
        switch entry.kind {
        case .package, .dependency, .packageOnly: DetailTab.allCases
        case .project, .handWritten, .notManaged: DetailTab.allCases.filter { $0 != .versions }
        }
    }

    /// `tab` when `tabs` has it, else Overview: a selection that the next row hides falls back to the first tab.
    nonisolated public static func resolve(_ tab: DetailTab, in tabs: [DetailTab]) -> DetailTab {
        tabs.contains(tab) ? tab : .overview
    }

    public var body: some View {
        Picker(DetailCopy.sections, selection: $selection) {
            ForEach(tabs, id: \.self) { tab in
                Text(DetailCopy.tab(tab)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(DetailCopy.sections)
    }
}

#Preview("DetailTabs, light") {
    @Previewable @State var tab = DetailTab.overview
    DetailTabs(selection: $tab)
        .padding(Spacing.l)
        .background(Color.surfaceWindow)
}

#Preview("DetailTabs, dark") {
    @Previewable @State var tab = DetailTab.security
    DetailTabs(selection: $tab)
        .padding(Spacing.l)
        .background(Color.surfaceWindow)
        .preferredColorScheme(.dark)
}
