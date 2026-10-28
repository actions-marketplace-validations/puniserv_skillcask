import SkillcaskDomain
import SwiftUI

/// The badges at the trailing edge of a sidebar scope row (Components board "Project row"): the count of
/// rows that are red or amber, coloured by the worst one, then a separate blue count of updates. Either badge
/// disappears at zero, and a healthy scope draws nothing at all.
public struct ScopeBadge: View {
    /// What the row shows for an `Attention`, derived once so the tests can pin it without a view.
    public struct Model: Hashable, Sendable {
        /// Rows that are error or warning (`Attention.needing`).
        public let needing: Int
        /// The attention badge's colour: the worst of error and warning, `nil` when nothing needs attention.
        public let attentionSeverity: Severity?
        /// Rows with an update (`Attention.updates`), always the separate blue badge.
        public let updates: Int

        public init(_ attention: Attention) {
            needing = attention.needing
            attentionSeverity = attention.needing > 0 ? attention.worst : nil
            updates = attention.updates
        }

        /// Whether the red or amber badge is drawn.
        public var showsAttention: Bool { attentionSeverity != nil }
        /// Whether the blue badge is drawn.
        public var showsUpdates: Bool { updates > 0 }
        /// A healthy scope: no badge, no reserved space.
        public var isHidden: Bool { !showsAttention && !showsUpdates }
    }

    public let attention: Attention

    public init(_ attention: Attention) {
        self.attention = attention
    }

    /// The derived model of `attention`.
    public var model: Model { Model(attention) }

    public var body: some View {
        let model = model
        if !model.isHidden {
            HStack(spacing: Spacing.xs) {
                if let severity = model.attentionSeverity {
                    CountBadge(model.needing, severity: severity)
                }
                CountBadge(model.updates, severity: .update)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview("ScopeBadge, light") {
    VStack(alignment: .trailing, spacing: Spacing.s) {
        ScopeBadge(DesignFixtures.api.attention)
        ScopeBadge(DesignFixtures.personal.attention)
        ScopeBadge(Attention(updates: 2))
        ScopeBadge(DesignFixtures.website.attention)
    }
    .padding(Spacing.l)
    .background(Color.surfaceSidebar)
}

#Preview("ScopeBadge, dark") {
    VStack(alignment: .trailing, spacing: Spacing.s) {
        ScopeBadge(DesignFixtures.api.attention)
        ScopeBadge(DesignFixtures.personal.attention)
        ScopeBadge(Attention(updates: 2))
        ScopeBadge(DesignFixtures.website.attention)
    }
    .padding(Spacing.l)
    .background(Color.surfaceSidebar)
    .preferredColorScheme(.dark)
}
