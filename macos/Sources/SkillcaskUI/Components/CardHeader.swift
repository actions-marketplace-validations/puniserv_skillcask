import SkillcaskDomain
import SwiftUI

/// The first line of an Overview card (Overview, Overview-States and Components boards, `.card h2`): an optional
/// status dot, the title with its status joined by a middle dot ("Health · 2 problems", 13 pt semibold), then at
/// the trailing end an optional quiet summary ("8 checks passed", 11 pt semibold in `textSecondary`: the boards'
/// `.t2` inherits the heading's weight) and whatever accessory the screen puts there (the Health card's Repair
/// and Sync buttons, a "Show in list" link). The header is the whole of a collapsed card, so it must read on its
/// own. Nothing truncates: the title takes its width first and wraps only when it alone is too long, the summary
/// wraps in what is left, trailing-aligned, and the accessory never shrinks; the dot sits on the first line.
///
/// The title is a plain button when `onTitleTap` is given ("Every card title links to the filtered list"); it
/// looks like text and tells VoiceOver what it opens. No board draws a chevron or disclosure on a card, so there
/// is none. The dot sits `Spacing.s` before the title, as the boards' `gap: 8px`, not the `Spacing.inline` of a
/// `StatusLabel`: the card title is a heading, not a status label.
public struct CardHeader<Accessory: View>: View {
    public let title: String
    /// What follows the title after the middle dot: `2 problems`, `none`, `all good`. Nil for a plain title.
    public let status: String?
    /// The dot before the title; nil draws no dot (Sources, Policy, Agents).
    public let severity: Severity?
    /// The quiet text at the trailing end: `8 checks passed`, `Repaired 2 items just now`.
    public let summary: String?
    public let onTitleTap: (() -> Void)?
    private let accessory: Accessory

    public init(
        title: String, status: String? = nil, severity: Severity? = nil, summary: String? = nil,
        onTitleTap: (() -> Void)? = nil, @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.status = status
        self.severity = severity
        self.summary = summary
        self.onTitleTap = onTitleTap
        self.accessory = accessory()
    }

    /// `Health · 2 problems`.
    public var titleText: String { CardCopy.title(title, status: status) }

    /// Whether the trailing summary draws: nil and empty both draw nothing.
    public var hasSummary: Bool { !(summary ?? "").isEmpty }

    /// Whether the title is a button: only when the screen gave it something to open.
    public var isTitleTappable: Bool { onTitleTap != nil }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            if let severity {
                StatusDot(severity)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            }
            titleView
                .anchorPreference(key: CardTitleAnchor.self, value: .bounds) { $0 }
            // The HStack's own gaps already separate title and summary; a zero minimum keeps Healthy's one-liners
            // ("Security · no findings  Nothing changed on disk") on one line in a 330 pt card.
            Spacer(minLength: 0)
            if hasSummary, let summary {
                Text(summary)
                    .font(Font.Token.captionSemibold)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            accessory
                .fixedSize()
                .layoutPriority(1)
        }
    }

    // MARK: - Subviews

    @ViewBuilder private var titleView: some View {
        if isTitleTappable, let onTitleTap {
            Button(action: onTitleTap) { titleLabel }
                .buttonStyle(.plain)
                .accessibilityHint(CardCopy.showsListHint)
        } else {
            titleLabel
        }
    }

    private var titleLabel: some View {
        Text(titleText)
            .font(Font.Token.bodyEmphasis)
            .foregroundStyle(Color.textPrimary)
            .layoutPriority(1)
    }
}

extension CardHeader where Accessory == EmptyView {
    /// A header with nothing after the summary.
    public init(
        title: String, status: String? = nil, severity: Severity? = nil, summary: String? = nil,
        onTitleTap: (() -> Void)? = nil
    ) {
        self.init(
            title: title, status: status, severity: severity, summary: summary, onTitleTap: onTitleTap
        ) {
            EmptyView()
        }
    }
}

#Preview("CardHeader, light") {
    VStack(alignment: .leading, spacing: Spacing.m) {
        CardHeader(title: "Health", status: "2 problems", severity: .error, onTitleTap: openList) {
            Button("Repair") {}.controlSize(.small)
        }
        CardHeader(title: "Health", status: "all good", severity: .ok, summary: "8 checks passed")
        CardHeader(title: "Sources")
    }
    .padding(Spacing.l)
    .background(Color.surfaceCard)
}

#Preview("CardHeader, dark") {
    VStack(alignment: .leading, spacing: Spacing.m) {
        CardHeader(title: "Health", status: "2 problems", severity: .error, onTitleTap: openList) {
            Button("Repair") {}.controlSize(.small)
        }
        CardHeader(title: "Health", status: "all good", severity: .ok, summary: "8 checks passed")
        CardHeader(title: "Sources")
    }
    .padding(Spacing.l)
    .background(Color.surfaceCard)
    .preferredColorScheme(.dark)
}

/// The title tap of a sample card: the screen opens the filtered list, a sample does nothing.
private func openList() {}
