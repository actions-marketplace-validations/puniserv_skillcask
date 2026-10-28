import SkillcaskDomain
import SwiftUI
import Testing

@testable import SkillcaskUI

/// The Overview card rules of P2-4: only an error card colours its border, the collapsed mode hides the body,
/// the header joins its title and status and knows whether it has a summary.
@Suite struct CardTests {
    private typealias PlainCard = CardContainer<EmptyView, EmptyView>

    @Test @MainActor func onlyErrorColoursTheBorder() throws {
        for scheme in [NSAppearance.Name.aqua, .darkAqua] {
            let errorBorder = try DesignTokensTests.hex(of: PlainCard.borderColor(for: .error), under: scheme)
            let errorDot = try DesignTokensTests.hex(of: Color.statusDot(.error), under: scheme)
            #expect(errorBorder == errorDot)
            let separator = try DesignTokensTests.hex(of: Color.separator, under: scheme)
            for severity in [Severity.warning, .update, .ok, .neutral] {
                #expect(try DesignTokensTests.hex(of: PlainCard.borderColor(for: severity), under: scheme) == separator)
            }
            #expect(try DesignTokensTests.hex(of: PlainCard.borderColor(for: nil), under: scheme) == separator)
        }
    }

    @Test @MainActor func errorBorderIsTheBoardsErrorDot() throws {
        #expect(try DesignTokensTests.hex(of: PlainCard.borderColor(for: .error), under: .aqua) == "#FF3B30")
        #expect(try DesignTokensTests.hex(of: PlainCard.borderColor(for: .error), under: .darkAqua) == "#FF6961")
        #expect(try DesignTokensTests.hex(of: PlainCard.borderColor(for: .warning), under: .aqua) == "#E3E3E8")
        #expect(try DesignTokensTests.hex(of: PlainCard.borderColor(for: .warning), under: .darkAqua) == "#353538")
    }

    @Test @MainActor func collapsedHidesTheBody() {
        let collapsed = CardContainer(title: "Health", severity: .ok, isCollapsed: true) { EmptyView() }
        #expect(!collapsed.showsBody)
        let expanded = CardContainer(title: "Health", severity: .error) { EmptyView() }
        #expect(expanded.showsBody)
        #expect(expanded.isCollapsed == false)
    }

    @Test @MainActor func cardBorderFollowsItsSeverity() throws {
        let error = CardContainer(title: "Health", severity: .error) { EmptyView() }
        #expect(try DesignTokensTests.hex(of: error.borderColor, under: .aqua) == "#FF3B30")
        let quiet = CardContainer(title: "Sources") { EmptyView() }
        #expect(try DesignTokensTests.hex(of: quiet.borderColor, under: .aqua) == "#E3E3E8")
    }

    @Test @MainActor func headerJoinsTitleAndStatus() {
        #expect(CardHeader(title: "Health", status: "2 problems").titleText == "Health · 2 problems")
        #expect(CardHeader(title: "Updates", status: "none").titleText == "Updates · none")
        #expect(CardHeader(title: "Sources").titleText == "Sources")
        #expect(CardHeader(title: "Sources", status: "").titleText == "Sources")
        #expect(CardCopy.title("Health", status: "all good") == "Health · all good")
    }

    @Test @MainActor func headerKnowsWhetherItHasASummary() {
        #expect(CardHeader(title: "Health", summary: "8 checks passed").hasSummary)
        #expect(!CardHeader(title: "Health").hasSummary)
        #expect(!CardHeader(title: "Health", summary: "").hasSummary)
        #expect(CardHeader(title: "Health", severity: .ok).severity == .ok)
        #expect(CardHeader(title: "Sources").severity == nil)
    }

    @Test @MainActor func titleIsTappableOnlyWithAnAction() {
        #expect(CardHeader(title: "Health", onTitleTap: {}).isTitleTappable)
        #expect(!CardHeader(title: "Sources").isTitleTappable)
        #expect(!CardHeader(title: "Sources", onTitleTap: nil).isTitleTappable)
        #expect(CardContainer(title: "Health", onTitleTap: {}, content: { EmptyView() }).onTitleTap != nil)
        #expect(CardContainer(title: "Sources") { EmptyView() }.onTitleTap == nil)
    }

    @Test func titleHintNamesTheList() {
        #expect(CardCopy.showsListHint == "Shows the filtered list")
        #expect(CardCopy.separator == " · ")
    }
}
