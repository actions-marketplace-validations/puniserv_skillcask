import SkillcaskDomain
import SwiftUI

/// The segmented filter above the list: one `FilterChip` per `Filter`, titles from `FilterCopy`, exactly one
/// active. "Needs attention" counts in the error colour, "Updates" in the update colour, the rest carry no badge.
/// A dimmed chip (List-States offline: "Updates" at 50 %) stays selectable but reads as unavailable.
public struct FilterChipBar: View {
    public let filters: [Filter]
    public let counts: [Filter: Int]
    public let dimmed: Set<Filter>
    @Binding public var selection: Filter

    /// List-States offline draws the Updates chip at `opacity: 0.5`.
    public static let dimmedOpacity: Double = 0.5

    public init(
        filters: [Filter] = Filter.allCases, counts: [Filter: Int] = [:], dimmed: Set<Filter> = [],
        selection: Binding<Filter>
    ) {
        self.filters = filters
        self.counts = counts
        self.dimmed = dimmed
        _selection = selection
    }

    /// The bar for a scope: counts from its `Attention` (rows needing a decision, rows with updates).
    public init(filters: [Filter] = Filter.allCases, attention: Attention, selection: Binding<Filter>) {
        self.init(filters: filters, counts: Self.counts(for: attention), selection: selection)
    }

    /// The chip counts an `Attention` yields: "Needs attention" is red plus amber, "Updates" the update count.
    nonisolated public static func counts(for attention: Attention) -> [Filter: Int] {
        [.needsAttention: attention.needing, .updates: attention.updates]
    }

    /// The badge colour of a filter's count.
    nonisolated public static func countSeverity(_ filter: Filter) -> Severity {
        switch filter {
        case .needsAttention: .error
        case .updates: .update
        case .all, .notManaged, .projectSkills: .neutral
        }
    }

    /// The chips scroll sideways rather than clip: five of them outgrow the 360 pt list column.
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.inline) {
                ForEach(filters, id: \.self) { filter in
                    FilterChip(
                        FilterCopy.title(filter), count: counts[filter], countSeverity: Self.countSeverity(filter),
                        isActive: selection == filter
                    ) {
                        selection = filter
                    }
                    .opacity(dimmed.contains(filter) ? Self.dimmedOpacity : 1)
                }
            }
        }
    }
}

/// Holds the selection the previews and the render tool bind to.
struct FilterChipBarSample: View {
    @State private var selection: Filter
    private let attention: Attention

    init(selection: Filter, attention: Attention) {
        _selection = State(initialValue: selection)
        self.attention = attention
    }

    var body: some View {
        FilterChipBar(attention: attention, selection: $selection)
    }
}

#Preview("FilterChipBar, light") {
    FilterChipBarSample(selection: .all, attention: Attention(errors: 3, warnings: 2, updates: 2))
        .padding(Spacing.l)
        .background(Color.surfaceWindow)
}

#Preview("FilterChipBar, dark") {
    FilterChipBarSample(selection: .needsAttention, attention: Attention(errors: 3, warnings: 2, updates: 2))
        .padding(Spacing.l)
        .background(Color.surfaceWindow)
        .preferredColorScheme(.dark)
}
