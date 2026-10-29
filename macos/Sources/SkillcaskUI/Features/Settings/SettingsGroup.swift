import SwiftUI

/// One rounded group of a Settings tab (Settings boards `.grp`): a card with a hairline border. Rows are separated
/// by a `SettingsSeparator` between them. `padded` is false for a group that draws its own insets (Advanced's
/// table).
struct SettingsGroup<Content: View>: View {
    var padded = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, padded ? Size.cardPaddingH : 0)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.l)
                .strokeBorder(Color.separator, lineWidth: Size.hairline)
        }
    }
}

/// The hairline between two rows of a group (`.fr{border-top:1px solid var(--sep)}`).
struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.separator)
            .frame(height: Size.hairline)
    }
}
