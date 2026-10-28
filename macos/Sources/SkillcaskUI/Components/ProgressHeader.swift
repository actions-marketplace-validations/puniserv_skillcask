import SwiftUI

/// The list-header progress of a short run (S11: Check, Sync, Refresh): the `MiniProgressBar` filling the row
/// with the run's title at its trailing end, as `List-States` "Stale while refreshing" draws it (11 pt,
/// `Color.textSecondary`). The caller passes the title ("Checking…", "Syncing…"); nothing here is copy.
public struct ProgressHeader: View {
    private let title: String

    /// - Parameter title: What is running, in the present progressive, from `Copy`.
    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        HStack(spacing: Spacing.s) {
            MiniProgressBar()
            Text(title)
                .font(Font.Token.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

#Preview("ProgressHeader, light") {
    ProgressHeader(title: "Checking…")
        .padding(Spacing.l)
        .frame(width: Size.listWidth)
        .background(Color.surfaceWindow)
}

#Preview("ProgressHeader, dark") {
    ProgressHeader(title: "Checking…")
        .padding(Spacing.l)
        .frame(width: Size.listWidth)
        .background(Color.surfaceWindow)
        .preferredColorScheme(.dark)
}
