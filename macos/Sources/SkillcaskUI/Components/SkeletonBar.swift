import SwiftUI

/// A static loading placeholder: the `.sk` bar of `Overview-States` "Loading" (10 pt tall, fully rounded,
/// `Color.skeleton`). The board shows still bars, so there is no shimmer. `width` is in points; `nil` fills
/// the available width, and `SkeletonLines` stacks bars at fractions of the container.
public struct SkeletonBar: View {
    /// The board's bar height (`.sk{height:10px}`); the radius is half of it, so the bar is a capsule.
    public nonisolated static let defaultHeight: CGFloat = 10

    private let width: CGFloat?
    private let height: CGFloat

    /// - Parameters:
    ///   - width: Points, or `nil` to fill the container.
    ///   - height: Defaults to `SkeletonBar.defaultHeight`.
    public init(width: CGFloat? = nil, height: CGFloat = SkeletonBar.defaultHeight) {
        self.width = width
        self.height = height
    }

    public var body: some View {
        Capsule()
            .fill(Color.skeleton)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .accessibilityHidden(true)
    }
}

#Preview("SkeletonBar, light") {
    VStack(alignment: .leading, spacing: Spacing.m) {
        SkeletonBar(width: 120)
        SkeletonBar()
    }
    .padding(Spacing.l)
    .frame(width: 320)
    .background(Color.surfaceWindow)
}

#Preview("SkeletonBar, dark") {
    VStack(alignment: .leading, spacing: Spacing.m) {
        SkeletonBar(width: 120)
        SkeletonBar()
    }
    .padding(Spacing.l)
    .frame(width: 320)
    .background(Color.surfaceWindow)
    .preferredColorScheme(.dark)
}
