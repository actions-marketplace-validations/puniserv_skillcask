import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// The Components board's "Attention badges" region (every severity, two- and three-digit counts, the
    /// two-badge pair and the small chip variant), and `ScopeBadge` on the three fixture scopes as sidebar rows.
    static let badges: [Entry] = [
        Entry(id: "P2-2", state: "badges", size: CGSize(width: 640, height: 150)) { AnyView(BadgesSample()) },
        Entry(id: "P2-2", state: "scope", size: CGSize(width: 220, height: 160)) { AnyView(ScopeSample()) },
    ]
}

/// The board region on the sidebar surface: a heading, then the badges on one line and the edge cases on another.
private struct BadgesSample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text("Attention badges").font(Font.Token.bodyEmphasis).foregroundStyle(Color.textPrimary)
                Text("sidebar and chips; worst severity wins; updates always separate")
                    .font(Font.Token.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            HStack(spacing: Spacing.m) {
                ForEach(Severity.allCases, id: \.self) { severity in
                    CountBadge(count(for: severity), severity: severity)
                }
                HStack(spacing: Spacing.xs) {
                    CountBadge(3, severity: .error)
                    CountBadge(2, severity: .update)
                }
                CountBadge(5, severity: .neutral, variant: .small)
                Text("· warning badge uses dark text · neutral small badge for chip counts")
                    .font(Font.Token.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            HStack(spacing: Spacing.m) {
                CountBadge(1, severity: .error)
                CountBadge(12, severity: .warning)
                CountBadge(123, severity: .update)
                CountBadge(999, severity: .error)
                CountBadge(0, severity: .error)
                Text("· one, two and three digits; a zero count draws nothing")
                    .font(Font.Token.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceSidebar)
    }

    /// The board's numbers per fill (3 red, 12 amber, 2 blue), a 1 for the two fills the board does not show.
    private func count(for severity: Severity) -> Int {
        switch severity {
        case .error: 3
        case .warning: 12
        case .update: 2
        case .ok, .neutral: 1
        }
    }
}

/// Three sidebar rows at the sidebar width: api (red and blue), My Skills (amber only), website (nothing).
private struct ScopeSample: View {
    var body: some View {
        VStack(spacing: 0) {
            row(DesignFixtures.apiScope, DesignFixtures.api.attention)
            row(DesignFixtures.personalScope, DesignFixtures.personal.attention)
            row(DesignFixtures.websiteScope, DesignFixtures.website.attention)
        }
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surfaceSidebar)
    }

    private func row(_ scope: DesignFixtures.ScopeLabel, _ attention: Attention) -> some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text(scope.name).font(Font.Token.bodyMedium).foregroundStyle(Color.textPrimary)
                Text(scope.path).font(Font.Token.caption).foregroundStyle(Color.textSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: Spacing.s)
            ScopeBadge(attention)
        }
        .padding(.horizontal, Spacing.s)
        .frame(width: Size.sidebarWidth, height: Size.sidebarRowSubtitle)
    }
}
