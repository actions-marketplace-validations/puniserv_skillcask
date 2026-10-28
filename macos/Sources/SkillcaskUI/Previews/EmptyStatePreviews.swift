import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// P2-11: the Overview's dashed hint blocks (no projects yet, folder without skills.toml) in the detail column,
    /// the list's empty and no-matches messages in the 360 pt list column, and the Contents tab's too-large and
    /// unreadable messages in the detail column.
    static let emptyStates: [Entry] = [
        Entry(id: "P2-11", state: "noProjects", size: EmptyStateSamples.overview) {
            AnyView(OverviewSample(EmptyStateSamples.noProjects))
        },
        Entry(id: "P2-11", state: "notSetUp", size: EmptyStateSamples.overview) {
            AnyView(OverviewSample(EmptyStateSamples.notSetUp))
        },
        Entry(id: "P2-11", state: "emptyList", size: EmptyStateSamples.list) {
            AnyView(ColumnSample(EmptyStateSamples.emptyList))
        },
        Entry(id: "P2-11", state: "noMatches", size: EmptyStateSamples.list) {
            AnyView(ColumnSample(EmptyStateSamples.noMatches))
        },
        Entry(id: "P2-11", state: "tooLarge", size: EmptyStateSamples.contents) {
            AnyView(ColumnSample(EmptyStateSamples.tooLarge))
        },
        Entry(id: "P2-11", state: "unreadable", size: EmptyStateSamples.contents) {
            AnyView(ColumnSample(EmptyStateSamples.unreadable))
        },
    ]
}

/// The six board states built from `EmptyCopy` and `DesignFixtures`; actions do nothing in a sample.
private enum EmptyStateSamples {
    /// The detail column of the 1280 pt boards (about 620 pt beside the sidebar and the list).
    static let detailWidth: CGFloat = 620
    static let overview = CGSize(width: detailWidth, height: 300)
    static let list = CGSize(width: Size.listWidth, height: 420)
    static let contents = CGSize(width: detailWidth, height: 380)

    @MainActor static var noProjects: EmptyState {
        EmptyState(
            icon: "folder.badge.plus", title: EmptyCopy.noProjectsTitle, body: EmptyCopy.noProjectsBody,
            actions: [
                .primary(EmptyCopy.openFolder, shortcutHint: EmptyCopy.openFolderShortcut) {},
                .secondary(EmptyCopy.findProjects) {},
            ],
            style: .dashed, textWidth: EmptyState.noProjectsTextWidth)
    }

    @MainActor static var notSetUp: EmptyState {
        EmptyState(
            icon: "folder.badge.questionmark", title: EmptyCopy.notSetUpTitle,
            body: EmptyCopy.notSetUpBody(agents: DesignFixtures.notSetUpAgents),
            actions: [.primary(EmptyCopy.setUp) {}, .secondary(EmptyCopy.removeFromSidebar) {}],
            style: .dashed, textWidth: EmptyState.notSetUpTextWidth)
    }

    @MainActor static var emptyList: EmptyState {
        EmptyState(
            icon: "shippingbox", title: EmptyCopy.noSkillsTitle, body: EmptyCopy.noSkillsBody,
            actions: [.primary(EmptyCopy.addSkill) {}])
    }

    @MainActor static var noMatches: EmptyState {
        let query = DesignFixtures.noMatchesQuery
        return EmptyState(
            icon: nil, title: EmptyCopy.noMatchesTitle(query: query),
            body: EmptyCopy.noMatchesBody(filter: .updates, matchesInAll: 1),
            actions: [.secondary(EmptyCopy.showAll) {}, .secondary(EmptyCopy.clearSearch) {}],
            link: .secondary(EmptyCopy.findInSources(query: query)) {})
    }

    @MainActor static var tooLarge: EmptyState {
        let file = DesignFixtures.apiDocsFile
        return EmptyState(
            icon: "doc.text", title: EmptyCopy.tooLargeTitle,
            body: EmptyCopy.tooLargeBody(fileName: file.name, bytes: file.bytes),
            actions: [.primary(EmptyCopy.openInEditor) {}], textWidth: EmptyState.tooLargeTextWidth)
    }

    @MainActor static var unreadable: EmptyState {
        let path: String? =
            if case .failed(_, _, _, let stderr) = DesignFixtures.unreadableFile.error { stderr } else { nil }
        return EmptyState(
            icon: "xmark.square", tone: .error,
            title: EmptyCopy.unreadableTitle(fileName: DesignFixtures.apiDocsFile.name),
            body: EmptyCopy.unreadableBody, detail: path,
            actions: [.secondary(EmptyCopy.openContainingFolder) {}, .primary(EmptyCopy.check) {}],
            link: .secondary(OutcomeCopy.details) {}, textWidth: EmptyState.unreadableTextWidth)
    }
}

/// The Overview detail body (`padding: 14px 20px`) on the panel's grouped ground (`.panel{background:
/// var(--grouped)}`): the dashed block, on the card surface, at the top of the column.
private struct OverviewSample: View {
    let state: EmptyState

    init(_ state: EmptyState) {
        self.state = state
    }

    var body: some View {
        state
            .padding(.vertical, Size.cardPaddingH)
            .padding(.horizontal, Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.surfaceGrouped)
    }
}

/// A list or Contents column with nothing to show: the plain message centred in it.
private struct ColumnSample: View {
    let state: EmptyState

    init(_ state: EmptyState) {
        self.state = state
    }

    var body: some View {
        state.background(Color.surfaceWindow)
    }
}
