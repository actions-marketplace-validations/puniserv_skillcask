import SwiftUI

/// One reach group of the Security tab (Components board, "Chip groups"; metrics from the Security board's
/// `.grp`): a `callout` label with the count ("Commands · 3") in `textSecondary`, centred on the first row of
/// chips, 10 pt before the items as 20 pt `.mono` pills (`.ch`) wrapping onto further lines. An empty group draws
/// nothing: "empty groups hidden".
public struct ChipGroup: View {
    /// What the group shows, and whether it shows at all.
    public struct Model: Hashable, Sendable {
        public let label: String
        public let items: [String]

        public init(label: String, items: [String]) {
            self.label = label
            self.items = items
        }

        /// The board hides a group with no items.
        public var isHidden: Bool { items.isEmpty }

        /// "Commands · 3", composed by `ReachCopy.title`.
        public var title: String { ReachCopy.title(label, count: items.count) }
    }

    public let model: Model
    /// A fixed label column so stacked groups align; `nil` lets the label take its own width.
    public let labelWidth: CGFloat?

    public init(_ model: Model, labelWidth: CGFloat? = nil) {
        self.model = model
        self.labelWidth = labelWidth
    }

    public init(label: String, items: [String], labelWidth: CGFloat? = nil) {
        self.init(Model(label: label, items: items), labelWidth: labelWidth)
    }

    public var body: some View {
        if !model.isHidden {
            HStack(alignment: .top, spacing: Spacing.rowGap) {
                Text(model.title)
                    .font(Font.Token.callout)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .frame(width: labelWidth, alignment: .leading)
                    .frame(minHeight: Size.reachChip)
                FlowLayout(spacing: Spacing.xs) {
                    ForEach(model.items, id: \.self) { item in
                        Pill(item, style: .mono)
                    }
                }
            }
        }
    }
}

/// The board's label column (`.lab{width:150px}`), for the previews and the render tool.
let chipGroupPreviewLabelWidth: CGFloat = 150

#Preview("ChipGroup, light") {
    VStack(alignment: .leading, spacing: Spacing.s) {
        ChipGroup(
            label: ReachCopy.label(.commands), items: ["pdftotext", "qpdf", "python3"],
            labelWidth: chipGroupPreviewLabelWidth)
        ChipGroup(label: ReachCopy.label(.network), items: ["pypi.org"], labelWidth: chipGroupPreviewLabelWidth)
        ChipGroup(label: ReachCopy.label(.env), items: [], labelWidth: chipGroupPreviewLabelWidth)
    }
    .padding(Spacing.l)
    .background(Color.surfaceWindow)
}

#Preview("ChipGroup, dark") {
    VStack(alignment: .leading, spacing: Spacing.s) {
        ChipGroup(
            label: ReachCopy.label(.commands), items: ["pdftotext", "qpdf", "python3"],
            labelWidth: chipGroupPreviewLabelWidth)
        ChipGroup(label: ReachCopy.label(.network), items: ["pypi.org"], labelWidth: chipGroupPreviewLabelWidth)
        ChipGroup(label: ReachCopy.label(.env), items: [], labelWidth: chipGroupPreviewLabelWidth)
    }
    .padding(Spacing.l)
    .background(Color.surfaceWindow)
    .preferredColorScheme(.dark)
}
