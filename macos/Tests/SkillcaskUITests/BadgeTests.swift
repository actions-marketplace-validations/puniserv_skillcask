import SkillcaskDomain
import SwiftUI
import Testing

@testable import SkillcaskUI

/// The sidebar badge rule: errors and warnings in one badge coloured by the worst, updates in a
/// separate blue one, nothing at zero; the badge text, its colours and what VoiceOver reads.
@Suite @MainActor struct BadgeTests {
    @Test func fixtureScopesShowTheBoardBadges() {
        let api = ScopeBadge(DesignFixtures.api.attention).model
        #expect(api.needing == 8 && api.attentionSeverity == .error && api.updates == 3)
        #expect(api.showsAttention && api.showsUpdates && !api.isHidden)

        let personal = ScopeBadge(DesignFixtures.personal.attention).model
        #expect(personal.needing == 12 && personal.attentionSeverity == .warning && personal.updates == 0)
        #expect(personal.showsAttention && !personal.showsUpdates)

        let website = ScopeBadge(DesignFixtures.website.attention).model
        #expect(website.isHidden && website.attentionSeverity == nil && website.needing == 0)
    }

    @Test func worstSeverityColoursTheAttentionBadge() {
        #expect(ScopeBadge.Model(Attention(errors: 1, warnings: 5)).attentionSeverity == .error)
        #expect(ScopeBadge.Model(Attention(warnings: 2)).attentionSeverity == .warning)
        let updatesOnly = ScopeBadge.Model(Attention(updates: 2))
        #expect(updatesOnly.attentionSeverity == nil && !updatesOnly.showsAttention && updatesOnly.showsUpdates)
        #expect(ScopeBadge.Model(Attention()).isHidden)
    }

    @Test func zeroDrawsNothing() {
        #expect(CountBadge.text(0) == nil)
        #expect(CountBadge.text(-1) == nil)
        #expect(CountBadge.text(1) == "1")
        #expect(CountBadge.text(12) == "12")
        #expect(CountBadge.text(123) == "123")
    }

    @Test func badgesReadAsCountsForVoiceOver() {
        #expect(Labels.badgeAttention(1) == "1 needs attention")
        #expect(Labels.badgeAttention(3) == "3 need attention")
        #expect(Labels.badgeUpdates(1) == "1 update")
        #expect(Labels.badgeUpdates(2) == "2 updates")
        #expect(CountBadge.accessibilityLabel(count: 8, severity: .error) == "8 need attention")
        #expect(CountBadge.accessibilityLabel(count: 12, severity: .warning) == "12 need attention")
        #expect(CountBadge.accessibilityLabel(count: 3, severity: .update) == "3 updates")
        #expect(CountBadge.accessibilityLabel(count: 5, severity: .neutral) == "5")
        #expect(CountBadge.accessibilityLabel(count: 1, severity: .ok) == "1")
    }

    @Test func minimumWidthEqualsHeightForBothVariants() {
        #expect(CountBadge.Variant.regular.height == Size.badge)
        #expect(CountBadge.Variant.small.height == Size.badgeSmall)
        for variant in [CountBadge.Variant.regular, .small] {
            #expect(variant.minWidth == variant.height)
        }
        #expect(CountBadge(3, severity: .error).variant == .regular)
    }

    @Test @MainActor func textIsWhiteExceptOnAmber() throws {
        for scheme in [NSAppearance.Name.aqua, .darkAqua] {
            #expect(try DesignTokensTests.hex(of: CountBadge.textColor(.warning), under: scheme) == "#3B2600")
            for severity in [Severity.error, .update, .ok, .neutral] {
                #expect(try DesignTokensTests.hex(of: CountBadge.textColor(severity), under: scheme) == "#FFFFFF")
            }
        }
    }
}
