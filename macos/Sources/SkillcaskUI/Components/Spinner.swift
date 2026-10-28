import SwiftUI

/// The system small spinner (`ProgressView().controlSize(.small)`) with an optional label beside it in
/// `Font.Token.callout` and `Color.textSecondary`, as the Loading strip of `Overview-States` draws
/// "Checking this project…". The boards sketch a 14 pt ring; the app uses the system indicator, not a drawing.
public struct Spinner: View {
    private let label: String?

    /// - Parameter label: Text beside the spinner, from `Copy`; `nil` shows the spinner alone.
    public init(label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        HStack(spacing: Spacing.s) {
            ProgressView()
                .controlSize(.small)
            if let label {
                Text(label)
                    .font(Font.Token.callout)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Spinner, light") {
    VStack(alignment: .leading, spacing: Spacing.m) {
        Spinner()
        Spinner(label: "Checking this project…")
    }
    .padding(Spacing.l)
    .background(Color.surfaceWindow)
}

#Preview("Spinner, dark") {
    VStack(alignment: .leading, spacing: Spacing.m) {
        Spinner()
        Spinner(label: "Checking this project…")
    }
    .padding(Spacing.l)
    .background(Color.surfaceWindow)
    .preferredColorScheme(.dark)
}
