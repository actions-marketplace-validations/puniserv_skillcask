import SkillcaskCore
import SkillcaskDomain
import SwiftUI

/// The Review Update sheet (S7: ReviewUpdate and ReviewUpdate-States boards) for one package or Update All, at
/// `Size.reviewSheet`. The header names the package and its versions with the Wrap checkbox and the find field,
/// then the callouts (tag moved, flagged lines, a version `update` does not reach); the body is the file list and
/// the diff pane, or the loading, up-to-date, fetch-failed or progress state; the footer says what Update does
/// and holds Cancel and Update.
///
/// `diff` loads when the sheet appears (`ReviewStore.load`, cancelled with the sheet). Update runs `update --
/// <the reviewed packages>` through `SheetRun`: its progress replaces the body in place, Cancel stops it until
/// the CLI reports done, exit 0 closes the sheet with the runner's toast, a failure stays here with the CLI's
/// message and hint. Update is the default button except when review-only (the tag moved): then Return does
/// nothing and Update is a plain button.
///
/// A failed update's banner offers Details, which discloses the run's transcript in the sheet
/// (`ReviewRunDetails`; Activity cannot open over the sheet), and Retry only where `FailureBanner` allows it
/// (never for an integrity failure). While `diff` runs, the title, a file-list skeleton and "Fetching changes for
/// 1.4.0…" show at once (Flow-F3).
struct ReviewUpdateSheet: View {
    /// What to review: one package (with the version the row offered, nil to let `diff` choose; `reviewOnly`
    /// when the tag moved, so Update is never the default button), or every update in range.
    enum Target: Hashable {
        case package(String, version: String?, reviewOnly: Bool)
        case all
    }

    /// The file list's width (ReviewUpdate board `width: 230px`).
    static let fileListWidth: CGFloat = 230
    /// The header's `padding: 16px 20px 12px`.
    static let headerPaddingTop = Spacing.l
    static let headerPaddingH = Spacing.xl
    static let headerPaddingBottom = Spacing.m
    /// The footer's `padding: 12px 20px`.
    static let footerPaddingV = Spacing.m
    static let footerPaddingH = Spacing.xl
    /// The find field's `width: 160px`.
    static let findWidth: CGFloat = 160
    /// The states' text column (`max-width: 380px`, ReviewUpdate-States).
    static let stateTextWidth: CGFloat = 380

    let target: Target
    let store: ScopeStore
    /// Closes the sheet (`AppStore.presentedSheet = nil`).
    let onClose: () -> Void

    @Environment(ActionRunner.self) private var runner
    /// The diff, the selection and find of this presentation.
    @State private var review: ReviewStore
    /// The sheet's mutation: progress in place, Cancel while running, close on success (`SheetRun`).
    @State private var run: SheetRun
    @State private var showsDetails = false
    /// The failed update's transcript is disclosed under the banner.
    @State private var showsRunDetails = false

    /// - Parameters:
    ///   - review: A prepared review (previews); nil builds one over `store` for `target`.
    ///   - run: A prepared run (previews); nil starts idle.
    ///   - showsRunDetails: The failed run's transcript starts disclosed (previews).
    init(
        target: Target, store: ScopeStore, onClose: @escaping () -> Void, review: ReviewStore? = nil,
        run: SheetRun? = nil, showsRunDetails: Bool = false
    ) {
        self.target = target
        self.store = store
        self.onClose = onClose
        _review = State(initialValue: review ?? Self.review(for: target, store: store))
        _run = State(initialValue: run ?? SheetRun())
        _showsRunDetails = State(initialValue: showsRunDetails)
    }

    static func review(for target: Target, store: ScopeStore) -> ReviewStore {
        switch target {
        case .package(let package, let version, let reviewOnly):
            ReviewStore(package: package, offeredVersion: version, reviewOnly: reviewOnly, store: store)
        case .all:
            ReviewStore(package: nil, store: store)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let failure = run.failure {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    FailureBanner(
                        failure, onDetails: runDetails == nil ? nil : { showsRunDetails.toggle() },
                        onRetry: startUpdate)
                    if showsRunDetails, let details = runDetails {
                        ReviewRunDetails(lines: details.lines, copyText: details.copy)
                    }
                }
                .padding(.horizontal, Self.headerPaddingH)
                .padding(.vertical, Spacing.m)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: Size.reviewSheet.width, height: Size.reviewSheet.height)
        .background(Color.surfaceWindow)
        .interactiveDismissDisabled(!run.canClose)
        .task(id: review.attempt) { await review.load() }
    }

    // MARK: - Header

    private var header: some View {
        @Bindable var review = review
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .center, spacing: Spacing.rowGap) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.rowGap) {
                    titleText
                        .lineLimit(1)
                        .layoutPriority(1)
                    // The progress state's header is the title and versions only (ReviewUpdate-States).
                    if !run.isRunning, let subtitle = review.subtitle {
                        Text(subtitle)
                            .font(Font.Token.callout)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: Spacing.s)
                if showsDiffTools {
                    HStack(spacing: Spacing.inline) {
                        Toggle(ReviewUpdateCopy.wrap, isOn: $review.wrapsLines)
                            .toggleStyle(.checkbox)
                            .font(Font.Token.callout)
                            .help(ReviewUpdateCopy.wrapHelp)
                        FindField(review: review)
                    }
                }
            }
            callouts
        }
        .padding(.top, Self.headerPaddingTop)
        .padding(.horizontal, Self.headerPaddingH)
        .padding(.bottom, Self.headerPaddingBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.separator).frame(height: Size.hairline)
        }
    }

    /// `Update pdf` with `1.2.0 → 1.4.0` in mono, or `Update 2 packages`.
    private var titleText: Text {
        let title = Text(review.titleWords).font(Font.Token.headline).foregroundStyle(Color.textPrimary)
        guard let versions = review.versions else { return title }
        return title + Text(" ") + Text(versions).font(Font.Token.mono).foregroundStyle(Color.textPrimary)
    }

    @ViewBuilder private var callouts: some View {
        if let move = review.tagMove {
            MessageStrip(
                .warning, title: VersionsCopy.tagMovedTitle(move.tag), text: VersionsCopy.tagMovedBody,
                symbol: MessageStrip.tagMovedSymbol, density: .strip)
        }
        // Only with new-version findings (planned capability); a pending update today has none (Q11 interim).
        if showsDiffTools, !review.flaggedLines.isEmpty {
            let counts = review.flagCounts
            MessageStrip(
                .warning, text: ReviewUpdateCopy.flagsCallout(risky: counts.risky, invisible: counts.invisible),
                emphasis: counts.risky > 0
                    ? ReviewUpdateCopy.riskyPatterns(counts.risky)
                    : ReviewUpdateCopy.invisibleCharacters(counts.invisible),
                density: .strip, trailing: .link(ReviewUpdateCopy.nextFlagged, action: review.nextFlaggedLine))
        }
        if let elsewhere = review.lockedElsewhere, !run.isRunning {
            MessageStrip(
                .info, text: ReviewUpdateCopy.elsewhere(locks: elsewhere.locks, offered: elsewhere.offered),
                density: .strip)
        }
    }

    // MARK: - Body

    @ViewBuilder private var content: some View {
        if let title = runningTitle {
            ReviewProgress(
                title: title, startedAt: run.action?.startedAt, lines: run.action?.lines.map(\.text) ?? [])
        } else {
            switch review.phase {
            case .loading:
                fetching
            case .failed(let message):
                fetchFailed(message)
            case .loaded:
                if review.isUpToDate {
                    upToDate
                } else {
                    diffPane
                }
            }
        }
    }

    private var diffPane: some View {
        HStack(spacing: 0) {
            ReviewFileList(review: review)
                .frame(width: Self.fileListWidth)
            Rectangle().fill(Color.separator).frame(width: Size.hairline)
            if let selection = review.selection, let file = review.selectedFile {
                DiffView(
                    file, flags: review.flags(for: file, in: selection.package), wrapsLines: review.wrapsLines,
                    matches: review.matchedLinesInSelection, currentMatch: review.currentMatchInSelection,
                    scrollTarget: scrollTarget(in: selection)
                )
                .id(selection)
            } else {
                Color.surfaceWindow
            }
        }
    }

    /// The title is already in the header; the file list's skeleton and the fetching line show until `diff`
    /// answers (Flow-F3 "Title and file list skeleton show at once").
    private var fetching: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if !review.isAll {
                    Text(ReviewUpdateCopy.filesHeading)
                        .font(Font.Token.captionSemibold)
                        .foregroundStyle(Color.textSecondary)
                }
                ForEach(Array(Self.skeletonFileWidths.enumerated()), id: \.offset) { _, width in
                    SkeletonBar(width: width)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ReviewFileList.headingPaddingH)
            .padding(.top, ReviewFileList.headingPaddingTop)
            .frame(width: Self.fileListWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.surfaceGrouped)
            Rectangle().fill(Color.separator).frame(width: Size.hairline)
            VStack(alignment: .leading, spacing: Spacing.l) {
                Spinner(label: review.fetchingText)
                SkeletonLines(count: Self.skeletonDiffLines)
                Spacer(minLength: 0)
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var upToDate: some View {
        EmptyState(
            icon: Self.upToDateSymbol, title: review.upToDateTitle, body: review.upToDateBody,
            textWidth: Self.stateTextWidth)
    }

    private func fetchFailed(_ message: UserMessage) -> some View {
        EmptyState(
            icon: FailureBanner.symbol(for: message), tone: .error, title: review.fetchFailedTitle,
            body: review.fetchFailedBody(message),
            link: message.details.map { _ in
                .secondary(OutcomeCopy.details) { showsDetails.toggle() }
            },
            disclosed: showsDetails ? message.details : nil, textWidth: Self.stateTextWidth)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            if let footnote = review.footnote {
                Text(footnote)
                    .font(Font.Token.callout)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.l)
            if review.isDoneAlone {
                // The board draws Done alone; Esc still closes the sheet.
                Button(SheetCopy.cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            } else {
                Button(SheetCopy.cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
            primaryButton
        }
        .controlSize(.regular)
        .padding(.vertical, Self.footerPaddingV)
        .padding(.horizontal, Self.footerPaddingH)
        .background(Color.surfaceGrouped)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.separator).frame(height: Size.hairline)
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch review.primaryButton(isRunning: run.isRunning, failure: run.failure) {
        case .done:
            Button(ReviewUpdateCopy.done, action: onClose)
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .keyboardShortcut(.defaultAction)
        case .retry:
            Button(OutcomeCopy.retry, action: review.retry)
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .keyboardShortcut(.defaultAction)
        case .update(isDefault: true, let isEnabled):
            Button(updateTitle, action: startUpdate)
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isEnabled)
        case .update(isDefault: false, let isEnabled):
            Button(updateTitle, action: startUpdate)
                .disabled(!isEnabled)
        }
    }

    // MARK: - Actions

    private func startUpdate() {
        showsRunDetails = false
        review.update(with: run, in: store, runner: runner, onSuccess: { onClose() })
    }

    /// Stops the run while one is in flight, else closes the sheet (a running `diff` is cancelled with it).
    private func cancel() {
        if run.canCancel {
            run.cancel()
        } else {
            onClose()
        }
    }
}

extension ReviewUpdateSheet {
    /// The up-to-date state's check mark (ReviewUpdate-States).
    fileprivate static let upToDateSymbol = "checkmark.circle"

    /// The file rows of the fetching skeleton (path widths, as the ReviewUpdate board's four files read).
    fileprivate static let skeletonFileWidths: [CGFloat] = [150, 120, 170, 96]
    /// The diff lines of the fetching skeleton.
    fileprivate static let skeletonDiffLines = 6

    /// The failed update's recorded run as the in-sheet Details shows it; nil when nothing was recorded (a
    /// refusal) and the message has no transcript of its own.
    fileprivate var runDetails: (lines: [String], copy: String)? {
        if let entry = run.failedEntry {
            let lines = ActivityCopy.commandLines(of: entry) + ActivityCopy.transcriptLines(of: entry)
            return (lines, ActivityCopy.copyText(of: entry))
        }
        guard let details = run.failure?.details else { return nil }
        return (details.components(separatedBy: "\n"), details)
    }

    /// Wrap and find show over a diff only.
    fileprivate var showsDiffTools: Bool {
        review.phase == .loaded && !review.isUpToDate && !run.isRunning
    }

    /// The run's title while it is in flight.
    fileprivate var runningTitle: String? {
        if case .running(let title) = run.phase { title } else { nil }
    }

    fileprivate var updateTitle: String {
        review.isAll ? ReviewUpdateCopy.updateAll(review.packages.count) : ReviewUpdateCopy.update
    }

    /// The store's focus when it is in the file on screen.
    fileprivate func scrollTarget(in selection: ReviewStore.FileID) -> DiffView.ScrollTarget? {
        guard let focus = review.focus, focus.line.file == selection else { return nil }
        return DiffView.ScrollTarget(line: focus.line.line, serial: focus.serial)
    }
}

/// The find field (ReviewUpdate board: 160 × 24, the 12 pt magnifier, `Find in diff`) with its match count and
/// the previous and next buttons (⇧⌘G, ⌘G); Return finds the next.
private struct FindField: View {
    @Bindable var review: ReviewStore

    var body: some View {
        HStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.inline) {
                Image(systemName: "magnifyingglass")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Size.iconInline, height: Size.iconInline)
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
                TextField(
                    ReviewUpdateCopy.findPlaceholder, text: $review.query,
                    prompt: Text(ReviewUpdateCopy.findPlaceholder).foregroundStyle(Color.textTertiary)
                )
                .textFieldStyle(.plain)
                .onSubmit(review.nextMatch)
            }
            .font(Font.Token.callout)
            .padding(.horizontal, Spacing.s)
            .frame(width: ReviewUpdateSheet.findWidth, height: Size.button)
            .background(Color.controlFill, in: RoundedRectangle(cornerRadius: Radius.m))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.m).strokeBorder(Color.controlBorder, lineWidth: Size.hairline))
            if !review.query.isEmpty {
                Text(countText)
                    .font(Font.Token.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                Button(action: review.previousMatch) {
                    Image(systemName: "chevron.up")
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .accessibilityLabel(ReviewUpdateCopy.findPrevious)
                .help(ReviewUpdateCopy.findPrevious)
                Button(action: review.nextMatch) {
                    Image(systemName: "chevron.down")
                }
                .keyboardShortcut("g", modifiers: .command)
                .accessibilityLabel(ReviewUpdateCopy.findNext)
                .help(ReviewUpdateCopy.findNext)
            }
        }
        .buttonStyle(.borderless)
    }

    private var countText: String {
        let count = review.matches.count
        guard count > 0 else { return ReviewUpdateCopy.noMatches }
        return ReviewUpdateCopy.matches((review.matchIndex ?? 0) + 1, of: count)
    }
}

extension AppStore.Sheet {
    /// The Versions tab's link: during a cooldown "Read the changes…" reads the waiting version review-only
    /// (`ReviewStore.readsWaitingVersion` runs `diff --to`, Update never offered); otherwise `update(for:)`.
    static func readChanges(of entry: SkillEntry) -> Self {
        guard let update = entry.update, update.available == nil, let cooldown = update.cooldown else {
            return .update(for: entry)
        }
        return .update(package: entry.package ?? entry.id, target: cooldown.version, reviewOnly: true)
    }
}
