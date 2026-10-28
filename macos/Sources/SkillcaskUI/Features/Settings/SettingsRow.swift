import SwiftUI

/// One row of a Settings group (Settings boards `.fr`): the label right-aligned in a 200 pt column, the control
/// after it, 12 pt apart, 10 pt above and below.
struct SettingsRow<Content: View>: View {
    let label: String
    var alignment: VerticalAlignment = .center
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: alignment, spacing: Spacing.m) {
            Text(label)
                .font(Font.Token.body)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(width: Size.settingsLabel, alignment: .trailing)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Spacing.rowGap)
    }
}

/// The 11 pt secondary line under a control or at the foot of a tab (Settings boards `.t2`).
struct SettingsCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Font.Token.caption)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The 12 pt secondary sentence beside a switch (Settings boards, `font-size: 12px; color: var(--text2)`).
struct SettingsNote: View {
    let text: Text

    init(_ text: String) {
        self.text = Text(text)
    }

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        text
            .font(Font.Token.callout)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A tab's body: the groups and footnotes stacked on the window background (Settings boards: `padding: 18px 20px
/// 22px; gap: 14px` → 20 and 16 here) at the Settings width.
struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            content
        }
        .padding(Spacing.xl)
        .frame(width: Size.settingsWidth, alignment: .topLeading)
        .background(Color.surfaceGrouped)
    }
}
