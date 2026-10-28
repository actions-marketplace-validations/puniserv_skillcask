import SwiftUI

/// One reach group of the Security tab (Components board, "Chip groups"): a `callout` label with the count
/// ("Commands · 3") in `textSecondary`, then the items as `.mono` pills wrapping onto further lines. An empty
/// group draws nothing: "empty groups hidden".
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
            HStack(alignment: .top, spacing: Spacing.s) {
                Text(model.title)
                    .font(Font.Token.callout)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .frame(width: labelWidth, alignment: .leading)
                FlowLayout(spacing: Spacing.xs) {
                    ForEach(model.items, id: \.self) { item in
                        Pill(item, style: .mono)
                    }
                }
            }
        }
    }
}

/// Lays subviews out left to right and wraps to a new line when the proposed width runs out.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: subviews, width: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    /// Each subview's frame at its ideal size, wrapped within `width`, origin at zero.
    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
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
