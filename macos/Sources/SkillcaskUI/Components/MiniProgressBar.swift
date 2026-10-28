import SwiftUI

/// The indeterminate 3 pt bar of `List-States` "Stale while refreshing" and `Running` "Short run": a
/// `Color.separator` track with `Radius.miniProgress` corners and a `Color.accent` segment 35 % of the track
/// wide that travels left to right and wraps. One of the five custom-drawn pieces; everything else that
/// spins is the system `Spinner`.
///
/// The segment's position is the pure function `offset(at:)` of the seconds since the bar appeared, so the
/// first frame (and a static render) shows the segment where the board draws it, at 30 % of the track.
/// With Reduce Motion on, the segment stays there.
public struct MiniProgressBar: View {
    /// The bar's height: `Size.miniProgress`.
    public nonisolated static let height = Size.miniProgress
    /// Segment width as a fraction of the track (board `width: 35%`).
    public nonisolated static let segmentFraction: CGFloat = 0.35
    /// Where the segment's leading edge rests at time zero (board `left: 30%`).
    public nonisolated static let restingOffset: CGFloat = 0.3
    /// Seconds for one left-to-right sweep.
    public nonisolated static let period: TimeInterval = 1.4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = Date()

    public init() {}

    /// The segment's leading edge as a fraction of the track width after `elapsed` seconds: starts at
    /// `restingOffset`, moves right at a constant speed, leaves the track at `1` and re-enters at
    /// `-segmentFraction`, so one sweep covers `1 + segmentFraction` in `period` seconds. Any `elapsed`,
    /// including negative, maps into `-segmentFraction..<1`.
    public nonisolated static func offset(at elapsed: TimeInterval) -> CGFloat {
        let travel = 1 + segmentFraction
        let restingPhase = (restingOffset + segmentFraction) / travel
        var phase = CGFloat(elapsed / period).truncatingRemainder(dividingBy: 1) + restingPhase
        phase = phase.truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }
        return -segmentFraction + phase * travel
    }

    public var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let elapsed = reduceMotion ? 0 : context.date.timeIntervalSince(appeared)
            GeometryReader { geometry in
                let width = geometry.size.width
                RoundedRectangle(cornerRadius: Radius.miniProgress)
                    .fill(Color.accent)
                    .frame(width: width * MiniProgressBar.segmentFraction)
                    .offset(x: width * MiniProgressBar.offset(at: elapsed))
            }
            .background(RoundedRectangle(cornerRadius: Radius.miniProgress).fill(Color.separator))
            .clipShape(RoundedRectangle(cornerRadius: Radius.miniProgress))
        }
        .frame(height: MiniProgressBar.height)
        .accessibilityHidden(true)
    }
}

#Preview("MiniProgressBar, light") {
    MiniProgressBar()
        .padding(Spacing.l)
        .frame(width: 360)
        .background(Color.surfaceWindow)
}

#Preview("MiniProgressBar, dark") {
    MiniProgressBar()
        .padding(Spacing.l)
        .frame(width: 360)
        .background(Color.surfaceWindow)
        .preferredColorScheme(.dark)
}
