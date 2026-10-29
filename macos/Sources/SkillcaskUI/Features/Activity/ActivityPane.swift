import AppKit
import SwiftUI

/// The list column with the Activity drawer under it (S15): `content` on top, the drawer at the bottom while
/// `ActionRunner.isActivityShown`, a drag on the drawer's top edge resizing it (the list keeps `minListHeight`).
/// Hidden by default; it consumes the runner's `detailsRequest` (the toast's "Show details", the banner's
/// Details), which is the only thing that opens it without the user asking for Activity itself.
struct ActivityPane<Content: View>: View {
    /// The board's drawer (`height: 300px`).
    static var defaultHeight: CGFloat { 300 }
    /// The header and one row stay visible.
    static var minHeight: CGFloat { 120 }
    /// What the drawer leaves to the list above it.
    static var minListHeight: CGFloat { 160 }

    @Environment(ActionRunner.self) private var runner
    @State private var height = Self.defaultHeight
    /// The height when the current drag began.
    @State private var dragStart: CGFloat?
    /// The resize cursor is pushed: popped on leaving the handle or when the drawer goes away under the pointer.
    @State private var cursorPushed = false
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            let maxHeight = max(Self.minHeight, proxy.size.height - Self.minListHeight)
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if runner.isActivityShown {
                    ActivityDrawer()
                        .frame(height: min(max(height, Self.minHeight), maxHeight))
                        .overlay(alignment: .top) { resizeHandle(maxHeight: maxHeight) }
                }
            }
        }
        .onChange(of: runner.detailsRequest, initial: true) { runner.consumeDetailsRequest() }
    }

    private func popCursor() {
        guard cursorPushed else { return }
        NSCursor.pop()
        cursorPushed = false
    }

    /// The drawer's top edge: a hairline to see, a taller strip to grab, the up-down cursor over it.
    private func resizeHandle(maxHeight: CGFloat) -> some View {
        Color.clear
            .frame(height: Spacing.s)
            .contentShape(Rectangle())
            .offset(y: -Spacing.xs)
            .onHover { inside in
                if inside, !cursorPushed {
                    NSCursor.resizeUpDown.push()
                    cursorPushed = true
                } else if !inside {
                    popCursor()
                }
            }
            .onDisappear { popCursor() }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStart ?? min(height, maxHeight)
                        dragStart = start
                        height = min(max(start - drag.translation.height, Self.minHeight), maxHeight)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .accessibilityElement()
            .accessibilityLabel(ActivityCopy.title)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: height = min(height + Spacing.xxxl, maxHeight)
                case .decrement: height = max(height - Spacing.xxxl, Self.minHeight)
                @unknown default: break
                }
            }
    }
}
