import SwiftUI

/// The detail's section tabs (Main board "Detail sections"): the system segmented control bound to a
/// `DetailTab`, titles from `DetailCopy`. Height and selection are the system's; the board's 22 pt is
/// `Size.tab` for layout maths only.
///
/// Declared deviation (Q9): the Main board draws an update count badge in the Versions segment ("Versions 1").
/// A system segmented `Picker` cannot host a badge view, and the system control is kept over a custom one; the
/// titles stay the four plain words. The blue strip under the tabs already carries the update, which the
/// designer's note names as "the only place that repeats the Versions tab".
public struct DetailTabs: View {
    @Binding public var selection: DetailTab

    public init(selection: Binding<DetailTab>) {
        _selection = selection
    }

    public var body: some View {
        Picker(DetailCopy.sections, selection: $selection) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
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
