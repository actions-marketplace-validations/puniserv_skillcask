import SkillcaskCore
import SwiftUI

extension PreviewRegistry {
    /// The message strips of the Components board, then each caller's strip at its column width: the list
    /// header offline line (S2), the first-launch not-managed banner (S1), the Contents invisible-character warning
    /// (S4), and the Overview tab's abandoned and offline lines (S3).
    static let strips: [Entry] = [
        Entry(id: "P2-7", state: "kinds", size: CGSize(width: 520, height: 220)) {
            AnyView(KindsSample())
        },
        Entry(id: "P2-7", state: "offline", size: CGSize(width: Size.listWidth, height: 120)) {
            AnyView(OfflineSample())
        },
        Entry(id: "P2-7", state: "notManaged", size: CGSize(width: StripFixtures.detailWidth, height: 120)) {
            AnyView(
                StripSample(horizontal: Size.columnPadding) {
                    MessageStrip(
                        .warning, title: StripCopy.notManagedTitle(count: StripFixtures.notManagedCount),
                        text: StripCopy.notManagedBody(count: StripFixtures.notManagedCount),
                        trailing: .button(StripCopy.review, action: {}))
                })
        },
        Entry(id: "P2-7", state: "contents", size: CGSize(width: StripFixtures.detailWidth, height: 120)) {
            AnyView(
                StripSample(horizontal: Size.columnPadding) {
                    MessageStrip(
                        .warning, text: StripCopy.invisibleCharacters, monoFragment: StripCopy.escapedOverride,
                        symbol: MessageStrip.invisibleSymbol, density: .strip,
                        trailing: .link(StripCopy.seeSecurity, action: {}))
                })
        },
        Entry(id: "P2-7", state: "abandoned", size: CGSize(width: StripFixtures.detailWidth, height: 120)) {
            AnyView(StripSample(horizontal: Spacing.xl) { AbandonedStrip() })
        },
        Entry(id: "P2-7", state: "detailOffline", size: CGSize(width: StripFixtures.detailWidth, height: 120)) {
            AnyView(
                StripSample(horizontal: Spacing.xl) {
                    MessageStrip(
                        .info, text: StripCopy.detailsOffline, density: .strip,
                        trailing: .button(OutcomeCopy.retry, action: {}))
                })
        },
    ]
}

/// The values the strip samples share.
private enum StripFixtures {
    /// The detail column the detail header previews use.
    static let detailWidth: CGFloat = 600

    /// My Skills' not-managed rows: 12 on Overview-States.
    @MainActor static var notManagedCount: Int {
        DesignFixtures.personal.entries.filter(\.isNotManaged).count
    }
}

/// One strip at a column's top, inset as its board insets it (`margin: 12px 24px 0` on Contents, `padding:
/// 12px 20px` on Detail-States).
private struct StripSample<Content: View>: View {
    private let horizontal: CGFloat
    private let content: Content

    init(horizontal: CGFloat, @ViewBuilder content: () -> Content) {
        self.horizontal = horizontal
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontal)
            .padding(.top, Spacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.surfaceWindow)
    }
}

/// legacy-lint's strip from `info.abandoned`, with the Add button only when a replacement is named.
private struct AbandonedStrip: View {
    private static let replacement: String? = {
        if case .replacedBy(let name) = DesignFixtures.legacyLintInfo.abandoned { return name }
        return nil
    }()

    var body: some View {
        MessageStrip(
            .warning, text: StripCopy.abandoned(replacement: Self.replacement), monoFragment: Self.replacement,
            symbol: MessageStrip.abandonedSymbol, density: .strip,
            trailing: Self.replacement.map { .button(StripCopy.addReplacement($0), action: {}) })
    }
}

/// The Components board's warning, info and error strips at the component sheet's width.
private struct KindsSample: View {
    private static let failure = ErrorCopy.message(
        for: DesignFixtures.signInBanner.error, title: DesignFixtures.signInBanner.title)

    var body: some View {
        VStack(spacing: Spacing.s) {
            MessageStrip(
                .warning, title: StripCopy.notManagedTitle(count: StripFixtures.notManagedCount),
                text: StripCopy.notManagedBody(count: StripFixtures.notManagedCount),
                trailing: .button(StripCopy.review, action: {}))
            MessageStrip(.info, title: StripCopy.offlineTitle, text: StripCopy.offlineBody)
            MessageStrip(
                .error, title: Self.failure.title, text: FailureBanner.bodyText(Self.failure),
                trailing: .button(OutcomeCopy.dismiss, action: {}))
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surfaceWindow)
    }
}

/// The list column while offline: the info strip in the header (`.lh` padding 12/10), then a lock-known row.
private struct OfflineSample: View {
    var body: some View {
        VStack(spacing: Spacing.s) {
            MessageStrip(.info, text: StripCopy.offlineHeader, density: .compact)
                .padding(.horizontal, Spacing.cardGap)
                .padding(.top, Spacing.m)
            VStack(spacing: Size.hairline) {
                SkillRow(DesignFixtures.entry("pdf", in: DesignFixtures.apiOffline), isOffline: true)
            }
            .padding(.horizontal, Spacing.inline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surfaceWindow)
    }
}
