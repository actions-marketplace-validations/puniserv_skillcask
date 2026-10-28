import SwiftUI

extension PreviewRegistry {
    /// P2-10: the Running board's toast at the bottom of the list column, the sign-in banner and the integrity
    /// banner at its top, and the Add Skill failure banners stacked at the sheet width.
    static let outcomes: [Entry] = [
        Entry(id: "P2-10", state: "toast", size: CGSize(width: Size.listWidth, height: 220)) {
            AnyView(ToastSample())
        },
        Entry(id: "P2-10", state: "banner", size: CGSize(width: Size.listWidth, height: 260)) {
            AnyView(BannerSample(DesignFixtures.signInBanner, onSignIn: {}))
        },
        Entry(id: "P2-10", state: "integrity", size: CGSize(width: Size.listWidth, height: 260)) {
            AnyView(BannerSample(DesignFixtures.integrityBanner))
        },
        Entry(id: "P2-10", state: "failures", size: CGSize(width: 520, height: 560)) {
            AnyView(FailuresSample())
        },
    ]
}

/// The list column after a run: three rows of the Running board, then the toast over the bottom edge.
private struct ToastSample: View {
    var body: some View {
        VStack(spacing: Size.hairline) {
            SkillRow(DesignFixtures.pdf)
            SkillRow(DesignFixtures.jiraSyntax)
            SkillRow(DesignFixtures.sqlReview)
        }
        .padding(Spacing.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surfaceWindow)
        .toast(.constant(ToastMessage(text: DesignFixtures.updatedToast.message, emphasis: "pdf")))
    }
}

/// A fixture banner at the top of the list column (the board's `margin: 8px 8px 0`), rows below it.
private struct BannerSample: View {
    private let banner: DesignFixtures.Banner
    private let onSignIn: (() -> Void)?

    init(_ banner: DesignFixtures.Banner, onSignIn: (() -> Void)? = nil) {
        self.banner = banner
        self.onSignIn = onSignIn
    }

    var body: some View {
        VStack(spacing: Spacing.s) {
            FailureBanner(
                ErrorCopy.message(for: banner.error, title: banner.title), onDetails: {}, onDismiss: {},
                onSignIn: onSignIn
            )
            .padding(.horizontal, Spacing.s)
            .padding(.top, Spacing.s)
            VStack(spacing: Size.hairline) {
                SkillRow(DesignFixtures.pdf)
                SkillRow(DesignFixtures.sqlReview)
            }
            .padding(.horizontal, Spacing.inline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surfaceWindow)
    }
}

/// The five Add Skill failures at the sheet's content width (`padding: 14px 16px`): not found, blocked by policy,
/// name clash, network unreachable, and an unreadable file.
private struct FailuresSample: View {
    private static let clash = DesignFixtures.nameClash

    var body: some View {
        VStack(spacing: Spacing.cardGap) {
            FailureBanner(
                ErrorCopy.message(
                    for: DesignFixtures.notFoundFailure.error, title: DesignFixtures.notFoundFailure.title),
                onDetails: {})
            FailureBanner(
                ErrorCopy.message(for: DesignFixtures.policyFailure.error, title: DesignFixtures.policyFailure.title))
            FailureBanner(
                ErrorCopy.nameClash(
                    existing: Self.clash.existing, existingPackage: Self.clash.existingPackage,
                    newPackage: Self.clash.newPackage))
            FailureBanner(ErrorCopy.message(for: DesignFixtures.unreachableFailure.error), onRetry: {})
            FailureBanner(
                ErrorCopy.message(for: DesignFixtures.unreadableFile.error, title: DesignFixtures.unreadableFile.title),
                onDetails: {}, onDismiss: {})
        }
        .padding(.vertical, Size.cardPaddingH)
        .padding(.horizontal, Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surfaceWindow)
    }
}
