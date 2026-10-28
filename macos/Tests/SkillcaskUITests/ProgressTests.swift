import SwiftUI
import Testing

@testable import SkillcaskUI

/// The pure parts of P2-8: the skeleton width pattern, the mini progress bar's segment position over time, and
/// the sizes the boards fix.
@Suite struct ProgressTests {
    // MARK: - Skeleton

    @Test func skeletonPatternCyclesTheBoardWidths() {
        #expect(SkeletonLines.pattern(count: 0) == [])
        #expect(SkeletonLines.pattern(count: 2) == [0.85, 0.6])
        #expect(SkeletonLines.pattern(count: 3) == SkeletonLines.defaultPattern)
        #expect(SkeletonLines.pattern(count: 5) == [0.85, 0.6, 0.4, 0.85, 0.6])
    }

    @Test func skeletonPatternStaysWithinTheContainer() {
        for fraction in SkeletonLines.pattern(count: 7) {
            #expect(fraction > 0 && fraction <= 1)
        }
    }

    @Test func skeletonLinesHeightCountsBarsAndGaps() {
        #expect(SkeletonLines.totalHeight(lines: 0, spacing: Spacing.s, barHeight: SkeletonBar.defaultHeight) == 0)
        #expect(SkeletonLines.totalHeight(lines: 1, spacing: Spacing.s, barHeight: SkeletonBar.defaultHeight) == 10)
        #expect(SkeletonLines.totalHeight(lines: 3, spacing: Spacing.s, barHeight: SkeletonBar.defaultHeight) == 46)
    }

    @Test func skeletonBarIsTheBoardsTenPointCapsule() {
        #expect(SkeletonBar.defaultHeight == 10)
    }

    // MARK: - Mini progress bar

    @Test func segmentRestsWhereTheBoardDrawsItAtTimeZero() {
        #expect(abs(MiniProgressBar.offset(at: 0) - MiniProgressBar.restingOffset) < 1e-9)
    }

    @Test func segmentMovesRightAndWrapsOncePerPeriod() {
        let period = MiniProgressBar.period
        let early = MiniProgressBar.offset(at: period * 0.1)
        let later = MiniProgressBar.offset(at: period * 0.3)
        #expect(later > early)
        #expect(abs(MiniProgressBar.offset(at: period) - MiniProgressBar.offset(at: 0)) < 1e-6)
        #expect(abs(MiniProgressBar.offset(at: period * 2.5) - MiniProgressBar.offset(at: period * 0.5)) < 1e-6)
    }

    @Test func segmentStaysOnOrJustOffTheTrackForAnyTime() {
        let lower = -MiniProgressBar.segmentFraction
        for step in -20...40 {
            let offset = MiniProgressBar.offset(at: Double(step) * 0.173)
            #expect(offset >= lower - 1e-9 && offset < 1 + 1e-9)
        }
    }

    @Test func segmentIsVisibleInTheFirstFrame() {
        let leading = MiniProgressBar.offset(at: 0)
        let trailing = leading + MiniProgressBar.segmentFraction
        #expect(leading >= 0 && trailing <= 1)
    }

    @Test func segmentSpeedIsConstant() {
        let period = MiniProgressBar.period
        let travel = 1 + MiniProgressBar.segmentFraction
        let delta = MiniProgressBar.offset(at: period * 0.2) - MiniProgressBar.offset(at: period * 0.1)
        #expect(abs(delta - travel * 0.1) < 1e-6)
    }

    @Test func barHeightsAreTheMiniProgressToken() {
        #expect(MiniProgressBar.height == Size.miniProgress)
        #expect(MiniProgressBar.height == 3)
        #expect(Radius.miniProgress == 2)
    }
}
