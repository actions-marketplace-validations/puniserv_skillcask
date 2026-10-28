import SwiftUI

/// The success toast of a run (S11; Running and Components boards): a card-coloured strip with a green check, the
/// outcome in 12 pt and the "Show details" link in the accent, 12 pt from the edges at the bottom of the list
/// column. It is the one surface besides popovers that carries a shadow (Tokens board `elev.2`). The caller
/// positions it; `View.toast(_:onDetails:)` does so and keeps the 4 s.
public struct Toast: View {
    /// How long a toast stays (Running board: "4 s, bottom of the list column, one at a time").
    public nonisolated static let duration: Duration = .seconds(4)
    /// The board's gap from the column edges (`left/right/bottom: 12px`).
    public nonisolated static let inset = Spacing.m

    /// The board's `elev.2` shadow (`0 8px 24px`, black at 0.16 light / 0.5 dark); a CSS blur of 24 is a SwiftUI
    /// radius of 12. Nothing in `DesignTokens` names a shadow yet; `docs/handoff/tokens.md` proposes
    /// `Shadow.popover` there, and these values move under it when that token lands.
    public enum Shadow {
        public nonisolated static let radius: CGFloat = 12
        public nonisolated static let yOffset: CGFloat = 8
        public nonisolated static let lightOpacity: Double = 0.16
        public nonisolated static let darkOpacity: Double = 0.5
    }

    nonisolated static let symbol = "checkmark.circle"

    @Environment(\.colorScheme) private var colorScheme

    private let text: String
    private let emphasis: String?
    private let onDetails: (() -> Void)?

    /// - Parameters:
    ///   - text: The outcome, from `OutcomeCopy`.
    ///   - emphasis: The part of `text` drawn semibold (the skill name).
    ///   - onDetails: What "Show details" does; nil hides the link.
    public init(_ text: String, emphasis: String? = nil, onDetails: (() -> Void)? = nil) {
        self.text = text
        self.emphasis = emphasis
        self.onDetails = onDetails
    }

    /// The toast of `message`; `onDetails` is wired only when the message shows the link.
    public init(_ message: ToastMessage, onDetails: (() -> Void)? = nil) {
        self.init(message.text, emphasis: message.emphasis, onDetails: message.showsDetails ? onDetails : nil)
    }

    public var body: some View {
        HStack(spacing: Spacing.rowGap) {
            // The board draws the check at 14 px; no 14 pt icon token exists, so the toolbar size (13) stands.
            Image(systemName: Self.symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Size.iconToolbar, height: Size.iconToolbar)
                .foregroundStyle(Color.statusOkText)
                .accessibilityHidden(true)
            Self.label(text, emphasis: emphasis)
                .font(Font.Token.callout)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDetails {
                Button(action: onDetails) {
                    Text(OutcomeCopy.showDetails)
                        .font(Font.Token.calloutMedium)
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Spacing.m)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .strokeBorder(Color.separator, lineWidth: Size.hairline)
        )
        .shadow(color: .black.opacity(shadowOpacity), radius: Shadow.radius, y: Shadow.yOffset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text)
    }

    // MARK: - Subviews

    private var shadowOpacity: Double {
        colorScheme == .dark ? Shadow.darkOpacity : Shadow.lightOpacity
    }

    /// `text` with its first `emphasis` in `Font.Token.calloutSemibold`, as the board bolds the skill name.
    nonisolated static func label(_ text: String, emphasis: String?) -> Text {
        guard let emphasis, !emphasis.isEmpty, let range = text.range(of: emphasis) else { return Text(text) }
        return Text(text[..<range.lowerBound])
            + Text(text[range]).font(Font.Token.calloutSemibold)
            + Text(text[range.upperBound...])
    }
}

extension View {
    /// Shows `message` as a `Toast` at the bottom of this view, `Toast.inset` from the edges, for `Toast.duration`;
    /// then clears the binding. A new message replaces the one showing and restarts the time; setting the binding
    /// to nil dismisses at once and cancels the timer. With Reduce Motion, the toast appears and leaves without
    /// moving.
    public func toast(
        _ message: Binding<ToastMessage?>, onDetails: @escaping (ToastMessage) -> Void = { _ in }
    ) -> some View {
        modifier(ToastPresenter(message: message, onDetails: onDetails))
    }
}

/// The overlay and the timer behind `View.toast`.
private struct ToastPresenter: ViewModifier {
    @Binding var message: ToastMessage?
    let onDetails: (ToastMessage) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Toast(message) { onDetails(message) }
                        .padding(Toast.inset)
                        .transition(transition)
                        .task(id: message.id) { await dismiss(after: Toast.duration, id: message.id) }
                }
            }
            .animation(reduceMotion ? nil : .default, value: message)
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    /// Sleeps for `duration`, then clears the binding if the same toast is still showing. `.task(id:)` cancels
    /// the sleep when the toast is replaced or dismissed, so a cancelled sleep clears nothing.
    private func dismiss(after duration: Duration, id: UUID) async {
        try? await Task.sleep(for: duration)
        guard !Task.isCancelled, message?.id == id else { return }
        message = nil
    }
}

#Preview("Toast, light") {
    Color.surfaceWindow
        .frame(width: Size.listWidth, height: 160)
        .toast(.constant(ToastMessage(text: "Updated pdf to 1.4.0", emphasis: "pdf")))
}

#Preview("Toast, dark") {
    Color.surfaceWindow
        .frame(width: Size.listWidth, height: 160)
        .toast(.constant(ToastMessage(text: "Updated pdf to 1.4.0", emphasis: "pdf")))
        .preferredColorScheme(.dark)
}
