import SkillcaskDomain
import SwiftUI

/// The tinted box of the Security boards (`.callout`: 10/12 padding, `Radius.l`, a 16 pt symbol in the status
/// text colour, 10 pt gap): a finding group, or the all-clear sentence. Unlike `MessageStrip` it holds several
/// lines and per-line buttons, so the content is the caller's.
struct SecurityCallout<Content: View>: View {
    let severity: Severity
    let symbol: String
    var alignment: VerticalAlignment = .top
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: alignment, spacing: Spacing.rowGap) {
            Image(systemName: symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Size.iconSidebar, height: Size.iconSidebar)
                .foregroundStyle(Color.statusText(severity))
                .accessibilityHidden(true)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Spacing.cardGap)
        .padding(.horizontal, Spacing.m)
        .background(Color.statusTint(severity), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }
}
