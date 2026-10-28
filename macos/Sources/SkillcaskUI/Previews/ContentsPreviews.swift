import SkillcaskCore
import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// P3-5: the detail column (header with Contents selected and the Contents tab) at 720 × 900 for the Contents
    /// board (my-notes, with the invisible-character strip and the risky line outlined), the long my-notes after
    /// Security's "Show in file" for its flagged line 49 (scrolled to and highlighted), and the three
    /// Contents-States panels (pdf after its update to 1.4.0, api-docs too large, deploy-checklist unreadable),
    /// the last once more with Details open. File facts are the fixtures' values, so nothing is read from disk.
    static let contents: [Entry] = [
        entry("normal") {
            ContentsSample(
                entry: DesignFixtures.myNotes, text: DesignFixtures.myNotesText, file: DesignFixtures.myNotesFile)
        },
        entry("showInFile") {
            ContentsSample(
                entry: DesignFixtures.myNotesLong, text: DesignFixtures.myNotesLongText,
                file: DesignFixtures.myNotesFile, targetLine: 49)
        },
        entry("pdf") {
            // Contents-States draws pdf installed at 1.4.0 with no update: the snapshot after Update.
            ContentsSample(
                entry: DesignFixtures.entry("pdf", in: DesignFixtures.apiUpdated), text: DesignFixtures.pdfText,
                file: DesignFixtures.pdfFile)
        },
        entry("tooLarge") {
            ContentsSample(
                entry: DesignFixtures.apiDocs, text: DesignFixtures.apiDocsText, file: DesignFixtures.apiDocsFile)
        },
        entry("unreadable") {
            ContentsSample(entry: DesignFixtures.deployChecklist, text: nil, file: nil)
        },
        entry("unreadableDetails") {
            ContentsSample(entry: DesignFixtures.deployChecklist, text: nil, file: nil, showsDetails: true)
        },
    ]

    private static func entry(_ state: String, _ make: @escaping @MainActor @Sendable () -> ContentsSample) -> Entry {
        Entry(id: "P3-5", state: state, size: CGSize(width: 720, height: 900)) { AnyView(make()) }
    }
}

/// One detail column over fixture data: the header with the Contents tab selected and the tab's body.
private struct ContentsSample: View {
    let entry: SkillEntry
    let text: SkillText?
    let file: DesignFixtures.SkillFile?
    /// Security's "Show in file" line: the block is scrolled to and highlighted.
    var targetLine: Int?
    /// Details open on the unreadable file.
    var showsDetails = false
    @State private var tab = DetailTab.contents

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(
                entry: entry, selectedTab: $tab, requiredBy: DesignFixtures.api.requirerSkills(of: entry))
            ContentsTab(
                entry: entry, detail: detail, root: Boot.apiScope.root,
                file: ContentsFile(
                    url: url, name: file?.name ?? ContentsFile.skillFileName, bytes: file?.bytes,
                    modified: file?.modified),
                targetLine: targetLine, showsDetails: showsDetails)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surfaceWindow)
    }

    private var url: URL? {
        ContentsTab.fileURL(root: Boot.apiScope.root, path: entry.path)
    }

    private var detail: SkillDetail {
        guard let text else {
            // What `ScopeStore` keeps when `FileHandle` cannot open the file: `ContentsCopy.readError`.
            let error = NSError(
                domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
                userInfo: [NSFilePathErrorKey: url?.path ?? ContentsFile.skillFileName])
            return SkillDetail(textError: ContentsCopy.readError(error))
        }
        return SkillDetail(text: text)
    }
}
