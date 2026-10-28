import SkillcaskCore
import SkillcaskDomain
import Testing

@testable import SkillcaskUI

/// P2-7: the strips say what the boards say, the not-managed count reads in the singular for one skill, each kind
/// draws its severity, and a strip has a trailing control only when the caller gives one with words.
@Suite struct StripCopyTests {
    @Test func boardSentencesAreVerbatim() {
        #expect(StripCopy.offlineHeader == "Offline: updates can’t be checked. Lock status is current.")
        #expect(StripCopy.offlineTitle == "Offline.")
        #expect(
            StripCopy.offlineBody == "Updates and details need a network connection; what the lock knows is shown.")
        #expect(
            StripCopy.invisibleCharacters
                == "This file contains invisible or direction-changing characters; they are shown escaped as "
                + "‹U+202E›. An agent reads them; you would not.")
        #expect(StripCopy.invisibleCharacters.contains(StripCopy.escapedOverride))
        #expect(StripCopy.seeSecurity == "See Security")
        #expect(StripCopy.review == "Review")
        #expect(
            StripCopy.detailsOffline
                == "Details need a network connection. Description, license, versions and dependencies will load "
                + "when you are back online.")
    }

    @Test func notManagedPluralises() {
        #expect(StripCopy.notManagedTitle(count: 12) == "12 skills on this Mac are not managed yet.")
        #expect(StripCopy.notManagedBody(count: 12) == "Adopt them to get updates and security checks.")
        #expect(StripCopy.notManagedTitle(count: 1) == "1 skill on this Mac is not managed yet.")
        #expect(StripCopy.notManagedBody(count: 1) == "Adopt it to get updates and security checks.")
        #expect(StripCopy.notManagedTitle(count: 2) == "2 skills on this Mac are not managed yet.")
    }

    @Test @MainActor func notManagedFixtureCountMatchesOverviewStates() {
        #expect(DesignFixtures.personal.entries.filter(\.isNotManaged).count == 12)
    }

    @Test func abandonedNamesTheReplacement() {
        #expect(StripCopy.abandoned(replacement: "acme/lint2") == "This package is abandoned. Use acme/lint2 instead.")
        #expect(StripCopy.abandoned(replacement: nil) == "This package is abandoned.")
        #expect(StripCopy.abandoned(replacement: "") == "This package is abandoned.")
        #expect(StripCopy.abandoned(InfoDocument.Abandoned?.none) == nil)
        #expect(StripCopy.abandoned(.withoutReplacement) == "This package is abandoned.")
        #expect(StripCopy.abandoned(.replacedBy("acme/lint2")) == "This package is abandoned. Use acme/lint2 instead.")
        #expect(StripCopy.addReplacement("acme/lint2") == "Add acme/lint2…")
    }

    @Test @MainActor func legacyLintFixtureNamesItsReplacement() {
        #expect(DesignFixtures.legacyLintInfo.abandoned == .replacedBy("acme/lint2"))
    }

    @Test func kindMapsToSeverity() {
        #expect(MessageStrip.Kind.info.severity == .update)
        #expect(MessageStrip.Kind.warning.severity == .warning)
        #expect(MessageStrip.Kind.error.severity == .error)
        #expect(MessageStrip.symbol(for: .info) == "info.circle")
        #expect(MessageStrip.symbol(for: .warning) == "exclamationmark.triangle")
        #expect(MessageStrip.symbol(for: .error) == "xmark.circle")
    }

    @Test @MainActor func trailingControlNeedsACallerAndWords() {
        #expect(MessageStrip(.info, text: StripCopy.offlineHeader, density: .compact).trailingTitle == nil)
        #expect(
            MessageStrip(.warning, text: "x", trailing: .button(StripCopy.review, action: {})).trailingTitle
                == "Review")
        #expect(
            MessageStrip(.warning, text: "x", trailing: .link(StripCopy.seeSecurity, action: {})).trailingTitle
                == "See Security")
        #expect(MessageStrip(.warning, text: "x", trailing: .button("", action: {})).trailingTitle == nil)
    }
}
