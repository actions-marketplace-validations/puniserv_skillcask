import Foundation
import Observation
import SkillcaskCore
import SkillcaskDomain

/// The model of one Review Update sheet (S7): the `diff` it reads, the file the pane shows, the Wrap toggle, the
/// find field and the flagged lines. One per sheet presentation, held by the sheet as `@State`; the update itself
/// runs through the sheet's `SheetRun`.
///
/// `diff` downloads, so it runs when the sheet appears (opening it was the user's explicit action), never earlier,
/// straight through the scope's `CLIClient`: a read-only command, so it does not wait for `MutationQueue`; the user
/// asked for it by opening the sheet, so each load is recorded in Activity (`recordActivity`: "Reviewed changes for
/// pdf 1.2.0 → 1.4.0"). Closing the sheet cancels the load's task, which terminates the child.
///
/// Flags (Q11 interim): `diff` has no JSON and `audit` describes only the installed version, whose line numbers
/// are the old file's, so a pending update shows no flags at all. The outline, the amber file dot and the callout
/// stay wired to `newVersionFindings`, which only the planned capability (findings of the new version, from the
/// CLI) fills; today only the `flags-planned` preview sets it.
///
/// Matches, flags and counts are computed once per diff (and per query for matches), not on every read (SUI-18).
@MainActor @Observable public final class ReviewStore {
    public enum Phase: Hashable, Sendable {
        /// `diff` is running.
        case loading
        /// `diff` answered; `diff` holds the packages (none: nothing to update).
        case loaded
        /// `diff` failed; the message says why, `error` keeps the CLI's error.
        case failed(UserMessage)
    }

    /// One file of one package: the file list's selection.
    public struct FileID: Hashable, Sendable {
        public let package: String
        public let path: String

        public init(package: String, path: String) {
            self.package = package
            self.path = path
        }
    }

    /// One row of one file: a find match or a flagged line.
    public struct LineRef: Hashable, Sendable {
        public let file: FileID
        public let line: DiffLine.ID
    }

    /// The row the pane scrolls to; `serial` changes on every jump so the same line can be jumped to twice.
    public struct Focus: Hashable, Sendable {
        public let line: LineRef
        public let serial: Int
    }

    /// The package asked for, as `diff` and `update` take it (a skill id is resolved to its package); nil for
    /// Update All.
    public let package: String?
    /// The skill id the sheet was asked for when it is not the package (`pdf` for anthropics/skills).
    private let requestedSkill: String?
    /// The version the row offered; `update` takes none, so the sheet says so when `diff` shows another.
    public let offeredVersion: String?
    /// Opened as review-only (the tag moved, Q3); see `isReviewOnly`.
    public let reviewOnlyRequested: Bool
    private let client: any CLIClient
    private let scope: Scope
    private let capabilities: Capabilities
    /// The scope's snapshot when the sheet opened: names, sources, agents, the tag note.
    private let snapshot: ScopeSnapshot?
    /// Where each `diff` load is recorded for Activity (S15); the scope store's, nil records nothing.
    @ObservationIgnored public var recordActivity: ActionRunner.ActivitySink?
    /// The selected row's `info` when the sheet opened, for the allowed range (`^1.2`).
    private let detailInfo: InfoDocument?

    // MARK: - State

    public private(set) var phase: Phase = .loading
    public private(set) var diff: UnifiedDiff?
    public private(set) var error: CLIError?
    /// Findings of the NEW version, by package: the planned capability; empty until the CLI provides them.
    public private(set) var newVersionFindings: [String: [AuditDocument.Finding]] = [:]
    /// The flags of each file, from `newVersionFindings`.
    public private(set) var flagsByFile: [FileID: [DiffFlag]] = [:]
    /// Every flagged row, in package, file and line order.
    public private(set) var flaggedLines: [LineRef] = []
    /// The flag counts of the whole review, for the callout.
    public private(set) var flagCounts: (risky: Int, invisible: Int) = (0, 0)
    /// Rows whose shown text contains the query, ignoring case, in package, file and line order.
    public private(set) var matches: [LineRef] = []
    public var selection: FileID?
    /// The Wrap checkbox; on, as the board draws it.
    public var wrapsLines = true
    /// The find field's text; editing it restarts at the first match.
    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            matches = Self.matches(of: query, in: packages)
            matchIndex = nil
            if !matches.isEmpty {
                goToMatch(0)
            }
        }
    }
    /// The current match in `matches`; nil before the first jump.
    public private(set) var matchIndex: Int?
    public private(set) var focus: Focus?
    /// Update All: the packages whose section is collapsed.
    public var collapsed: Set<String> = []
    /// Bumped by Retry; the sheet's `.task(id:)` loads again.
    public private(set) var attempt = 0

    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var generation = 0

    /// - Parameters:
    ///   - package: The package or skill id asked for; nil for Update All.
    ///   - offeredVersion: The version the row offered, nil to let `diff` choose.
    ///   - reviewOnly: The tag moved: Update is never the default button.
    public init(
        package: String?, offeredVersion: String? = nil, reviewOnly: Bool = false, client: any CLIClient,
        scope: Scope, capabilities: Capabilities, snapshot: ScopeSnapshot?, detailInfo: InfoDocument? = nil
    ) {
        let resolved = package.map { Self.resolvePackage($0, in: snapshot) }
        self.package = resolved
        requestedSkill = resolved == package ? nil : package
        self.offeredVersion = offeredVersion
        reviewOnlyRequested = reviewOnly
        self.client = client
        self.scope = scope
        self.capabilities = capabilities
        self.snapshot = snapshot
        self.detailInfo = detailInfo
    }

    /// The sheet over `store`'s scope, client and snapshot.
    public convenience init(
        package: String?, offeredVersion: String? = nil, reviewOnly: Bool = false, store: ScopeStore
    ) {
        self.init(
            package: package, offeredVersion: offeredVersion, reviewOnly: reviewOnly, client: store.client,
            scope: store.scope, capabilities: store.capabilities, snapshot: store.snapshot,
            detailInfo: store.detail?.info)
        recordActivity = store.recordActivity
    }

    // MARK: - Derived

    /// Update All.
    public var isAll: Bool {
        package == nil
    }

    public var packages: [UnifiedDiff.Package] {
        diff?.packages ?? []
    }

    /// `diff` answered with nothing newer in range.
    public var isUpToDate: Bool {
        phase == .loaded && packages.isEmpty
    }

    /// What the title and the toast call a package: its one skill (`pdf`), else the package.
    public func name(of package: String) -> String {
        if let diffPackage = packages.first(where: { $0.name == package }),
            let name = Self.skillName(of: diffPackage)
        {
            return name
        }
        if package == self.package, let requestedSkill {
            return requestedSkill
        }
        let entries = snapshot?.entries.filter { $0.package == package } ?? []
        if entries.count == 1 {
            return entries[0].name
        }
        // A package with several skills in this scope (anthropics/skills: pdf, test-writer): the one row offering
        // the update names it.
        let updating = entries.filter { if case .updateAvailable = $0.health { true } else { false } }
        return updating.count == 1 ? updating[0].name : package
    }

    /// The single package's name for the title (`pdf`); nil for Update All.
    public var displayName: String? {
        package.map(name(of:))
    }

    /// The package's one row in the snapshot, for its source, version, range and tag note.
    public var entry: SkillEntry? {
        guard let package else { return nil }
        let entries = snapshot?.entries.filter { $0.package == package } ?? []
        return entries.first { $0.name == displayName } ?? entries.first
    }

    /// The moved tag of the package's update, from `outdated`'s note.
    public var tagMove: VersionsModel.TagMove? {
        entry?.update?.note.flatMap(VersionsModel.TagMove.init(note:))
    }

    /// Review-only: asked so, or the tag moved. Update stays offered but is never the default button (Q3).
    public var isReviewOnly: Bool {
        reviewOnlyRequested || tagMove != nil
    }

    /// Update is the default (Return) button: never while review-only.
    public var updateIsDefault: Bool {
        !isReviewOnly
    }

    /// The version `update` locks when it differs from the one the row offered; nil when they agree.
    public var lockedElsewhere: (locks: String, offered: String)? {
        guard let offeredVersion, let first = packages.first, !isAll, first.to != offeredVersion else { return nil }
        return (first.to, offeredVersion)
    }

    /// The agents the scope links to (`Claude Code`, `Cursor`).
    public var agents: [String] {
        snapshot?.targets?.entries.map(ShellCopy.agentName) ?? []
    }

    /// Skills left out because their newer version waits for the minimum release age (Update All's note):
    /// nothing newer in range (`within` is the lock) and a cooldown end known, grouped by the waiting version.
    public var waiting: [(skills: [String], version: String?)] {
        let inDiff = Set(packages.map(\.name))
        var groups: [(skills: [String], version: String?)] = []
        for entry in snapshot?.entries ?? [] {
            guard let package = entry.package, !inDiff.contains(package), let update = entry.update,
                update.eligible != nil, update.available == nil
            else { continue }
            if let index = groups.firstIndex(where: { $0.version == update.latest }) {
                groups[index].skills.append(entry.name)
            } else {
                groups.append(([entry.name], update.latest))
            }
        }
        return groups
    }

    public func file(_ id: FileID) -> UnifiedDiff.File? {
        packages.first { $0.name == id.package }?.files.first { $0.path == id.path }
    }

    public var selectedFile: UnifiedDiff.File? {
        selection.flatMap(file)
    }

    /// The flags of one file of `package`; none unless new-version findings exist.
    public func flags(for file: UnifiedDiff.File, in package: String) -> [DiffFlag] {
        flagsByFile[FileID(package: package, path: file.path)] ?? []
    }

    /// Findings of the new version exist (planned capability), so flag counts mean something.
    public var hasNewVersionFindings: Bool {
        newVersionFindings.values.contains { !$0.isEmpty }
    }

    /// The flagged lines of one package.
    public func flaggedCount(of package: UnifiedDiff.Package) -> Int {
        package.files.reduce(0) { $0 + flags(for: $1, in: package.name).count }
    }

    /// The matched rows of the selected file, for the pane's outline.
    public var matchedLinesInSelection: Set<DiffLine.ID> {
        guard let selection else { return [] }
        return Set(matches.filter { $0.file == selection }.map(\.line))
    }

    /// The current match's row in the selected file.
    public var currentMatchInSelection: DiffLine.ID? {
        guard let matchIndex, matches.indices.contains(matchIndex), matches[matchIndex].file == selection else {
            return nil
        }
        return matches[matchIndex].line
    }

    // MARK: - Summaries (pure)

    /// The files the boards count: every file with text lines (`4 files` leaves out the binary sample.pdf).
    nonisolated public static func countedFiles(_ package: UnifiedDiff.Package) -> [UnifiedDiff.File] {
        package.files.filter { [.added, .modified, .removed].contains($0.change) }
    }

    /// `+31 −9`: the lines of added and modified files; a removed file shows `removed` instead of counts, so its
    /// lines are left out, as the board's total does.
    nonisolated public static func totals(_ package: UnifiedDiff.Package) -> (additions: Int, deletions: Int) {
        package.files.filter { $0.change == .added || $0.change == .modified }
            .reduce((0, 0)) { ($0.0 + $1.additions, $0.1 + $1.deletions) }
    }

    /// The file list's counts for a file: `+17` for a new file, `−6`, `+14 −3`; nil when the list shows a word.
    nonisolated public static func listCounts(_ file: UnifiedDiff.File) -> (additions: Int, deletions: Int)? {
        switch file.change {
        case .added, .modified: (file.additions, file.deletions)
        case .removed, .binary, .tooLarge, .modeOnly: nil
        }
    }

    /// The one skill folder every file of `package` sits in (`pdf/…` → `pdf`); nil for several or none.
    nonisolated public static func skillName(of package: UnifiedDiff.Package) -> String? {
        let folders = Set(package.files.compactMap { file in file.path.split(separator: "/").first.map(String.init) })
        guard folders.count == 1, let folder = folders.first, package.files.allSatisfy({ $0.path.contains("/") })
        else { return nil }
        return folder
    }

    /// A skill id becomes its package (`pdf` → `anthropics/skills`); anything else is taken as a package name.
    nonisolated static func resolvePackage(_ name: String, in snapshot: ScopeSnapshot?) -> String {
        guard snapshot?.entries.contains(where: { $0.package == name }) != true,
            let entry = snapshot?.entries.first(where: { $0.id == name }), let package = entry.package
        else { return name }
        return package
    }

    /// Rows of `packages` whose shown text contains `query`, ignoring case.
    nonisolated static func matches(of query: String, in packages: [UnifiedDiff.Package]) -> [LineRef] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return packages.flatMap { package in
            package.files.flatMap { file in
                let id = FileID(package: package.name, path: file.path)
                return DiffView.rows(for: file)
                    .filter { DiffCopy.shown($0.text).localizedCaseInsensitiveContains(needle) }
                    .map { LineRef(file: id, line: $0.id) }
            }
        }
    }

    /// The flags, flagged rows and counts of `packages` from new-version findings.
    nonisolated static func flags(
        in packages: [UnifiedDiff.Package], findings: [String: [AuditDocument.Finding]]
    ) -> (byFile: [FileID: [DiffFlag]], lines: [LineRef], risky: Int, invisible: Int) {
        var byFile: [FileID: [DiffFlag]] = [:]
        var lines: [LineRef] = []
        var risky = 0
        var invisible = 0
        for package in packages {
            guard let found = findings[package.name], !found.isEmpty else { continue }
            for file in package.files {
                let flags = DiffFlag.flags(for: file, findings: found)
                guard !flags.isEmpty else { continue }
                let id = FileID(package: package.name, path: file.path)
                byFile[id] = flags
                risky += flags.filter { $0.kind == .risky }.count
                invisible += flags.filter { $0.kind == .invisible }.count
                let byLine = DiffView.flagsByLine(flags)
                lines += DiffView.rows(for: file)
                    .compactMap { row in
                        guard let number = row.newNumber, byLine[number] != nil else { return nil }
                        return LineRef(file: id, line: row.id)
                    }
            }
        }
        return (byFile, lines, risky, invisible)
    }

    // MARK: - Load

    /// `diff [-- package]`, once per attempt: what the sheet's `.task(id: attempt)` runs. A preloaded or loaded
    /// review runs nothing; a cancelled load (the sheet closed) records nothing.
    public func load() async {
        guard phase == .loading else { return }
        generation += 1
        let mine = generation
        let startedAt = Date()
        var trace = ActionRunner.ReadTrace(command: ActionCopy.unbuilt)
        let outcome: Result<UnifiedDiff, CLIError>
        do {
            let invocation = try Invocation(.diff(package: package), in: scope, capabilities: capabilities)
            trace.command = invocation.displayCommand
            let result = try await client.run(invocation)
            trace.status = result.status
            trace.stderr = result.stderr
            trace.environmentOverrides = result.environmentOverrides
            if let failure = result.failure() {
                outcome = .failure(failure)
            } else {
                outcome = .success(UnifiedDiff(text: result.stdoutText))
            }
        } catch {
            outcome = .failure(error)
        }
        record(outcome, trace: trace, startedAt: startedAt)
        guard mine == generation, !Task.isCancelled else { return }
        switch outcome {
        case .success(let diff):
            show(diff)
        case .failure(.cancelled):
            break
        case .failure(let error):
            fail(error)
        }
    }

    /// Hands the load's row to `recordActivity`: what was reviewed, or the sheet's own failure title.
    private func record(_ outcome: Result<UnifiedDiff, CLIError>, trace: ActionRunner.ReadTrace, startedAt: Date) {
        guard let recordActivity else { return }
        let headline: String
        var error: CLIError?
        switch outcome {
        case .success(let diff):
            if diff.packages.count > 1 {
                headline = ActivityCopy.reviewedAll(diff.packages.count)
            } else if let only = diff.packages.first {
                headline = ActivityCopy.reviewed(Self.skillName(of: only) ?? only.name, from: only.from, to: only.to)
            } else {
                headline =
                    isAll ? ActivityCopy.reviewedAll(0) : ActivityCopy.reviewed(displayName ?? "", from: nil, to: nil)
            }
        case .failure(let failure):
            headline = ""
            error = failure
        }
        let failure =
            isAll
            ? ReviewUpdateCopy.fetchFailedAll
            : ReviewUpdateCopy.fetchFailed(version: offeredVersion, name: displayName ?? package ?? "")
        recordActivity(
            .read(
                headline: headline, failure: failure, scope: scope, startedAt: startedAt, traces: [trace],
                error: error, expectsDocument: false))
    }

    /// Retry after a failed fetch: back to loading, and a new attempt for the sheet's task.
    public func retry() {
        guard case .failed = phase else { return }
        phase = .loading
        error = nil
        attempt += 1
    }

    /// Previews and tests: the answer of `diff` without running it. `newVersionFindings` stands for the planned
    /// capability (findings of the new version from the CLI); no shipped path passes it.
    public func preload(_ diff: UnifiedDiff, newVersionFindings: [String: [AuditDocument.Finding]] = [:]) {
        self.newVersionFindings = newVersionFindings
        show(diff)
    }

    /// Previews and tests: a failed `diff`.
    public func preload(failure error: CLIError) {
        fail(error)
    }

    private func show(_ diff: UnifiedDiff) {
        self.diff = diff
        error = nil
        phase = .loaded
        let flags = Self.flags(in: diff.packages, findings: newVersionFindings)
        flagsByFile = flags.byFile
        flaggedLines = flags.lines
        flagCounts = (flags.risky, flags.invisible)
        matches = Self.matches(of: query, in: diff.packages)
        if selection.flatMap(file) == nil {
            selection = packages.first.flatMap { package in
                package.files.first.map { FileID(package: package.name, path: $0.path) }
            }
        }
    }

    private func fail(_ error: CLIError) {
        self.error = error
        phase = .failed(ErrorCopy.message(for: error))
    }

    // MARK: - Navigation

    /// Find's next match, wrapping to the first.
    public func nextMatch() {
        guard !matches.isEmpty else { return }
        goToMatch(matchIndex.map { ($0 + 1) % matches.count } ?? 0)
    }

    /// Find's previous match, wrapping to the last.
    public func previousMatch() {
        guard !matches.isEmpty else { return }
        goToMatch(matchIndex.map { ($0 - 1 + matches.count) % matches.count } ?? matches.count - 1)
    }

    /// The callout's "Next flagged line ↓": the first flagged row after the one in focus, wrapping.
    public func nextFlaggedLine() {
        let flagged = flaggedLines
        guard !flagged.isEmpty else { return }
        let order = flagged.map(position)
        let here = focus.map { position($0.line) }
        let next = here.flatMap { here in order.firstIndex { here.lexicographicallyPrecedes($0) } } ?? 0
        jump(to: flagged[next])
    }

    private func goToMatch(_ index: Int) {
        let all = matches
        guard all.indices.contains(index) else { return }
        matchIndex = index
        jump(to: all[index])
    }

    private func jump(to line: LineRef) {
        selection = line.file
        if let package = packages.first(where: { $0.name == line.file.package }) {
            collapsed.remove(package.name)
        }
        serial += 1
        focus = Focus(line: line, serial: serial)
    }

    /// A row's place in the review: package, file, line.
    private func position(_ line: LineRef) -> [Int] {
        let packageIndex = packages.firstIndex { $0.name == line.file.package } ?? 0
        let fileIndex =
            packages.indices.contains(packageIndex)
            ? packages[packageIndex].files.firstIndex { $0.path == line.file.path } ?? 0 : 0
        return [packageIndex, fileIndex, line.line]
    }

    // MARK: - Presentation

    /// The footer's primary button, decided here so the view only draws it (and the rule is testable).
    public enum PrimaryButton: Hashable, Sendable {
        /// Nothing to update: Done closes (Return and Esc).
        case done
        /// `diff` failed: Retry loads again.
        case retry
        /// Update; `isDefault` is false while review-only, so Return never updates; disabled unless loaded with
        /// packages and nothing runs.
        case update(isDefault: Bool, isEnabled: Bool)
    }

    /// The primary button while the sheet's run is (`isRunning`) or is not in flight.
    public func primaryButton(isRunning: Bool) -> PrimaryButton {
        if isUpToDate {
            return .done
        }
        if case .failed = phase, !isRunning {
            return .retry
        }
        return .update(isDefault: updateIsDefault, isEnabled: phase == .loaded && !packages.isEmpty && !isRunning)
    }

    /// The title words: `Update pdf`, `Update 2 packages`; `Update All` until the packages are known.
    public var titleWords: String {
        if let displayName {
            return ReviewUpdateCopy.title(package: displayName)
        }
        return phase == .loaded && !isUpToDate
            ? ReviewUpdateCopy.updateAllTitle(count: packages.count) : ReviewUpdateCopy.updateAllTitle
    }

    /// `1.2.0 → 1.4.0` once `diff` named the versions; before that (loading, fetch failed) the installed version
    /// and the one the row offered. Nil for Update All and once `diff` found nothing newer.
    public var versions: String? {
        guard !isAll else { return nil }
        if let package = packages.first {
            return ReviewUpdateCopy.versions(from: package.from, to: package.to)
        }
        guard phase != .loaded, let from = entry?.version, let to = offeredVersion, from != to else { return nil }
        return ReviewUpdateCopy.versions(from: from, to: to)
    }

    /// `anthropics/skills · GitHub · 4 files · +31 −9`; `api · pdf, review-pr · 7 files` for Update All; nil
    /// until a diff with packages is loaded.
    public var subtitle: String? {
        guard phase == .loaded, !isUpToDate else { return nil }
        let files = packages.reduce(0) { $0 + Self.countedFiles($1).count }
        if isAll {
            return ReviewUpdateCopy.updateAllSubtitle(
                scope: ShellCopy.name(of: scope), names: packages.map { name(of: $0.name) }, files: files)
        }
        guard let package = packages.first else { return nil }
        let totals = Self.totals(package)
        let source = entry.flatMap(SourceKind.kind(of:)).map(SourceCopy.label)
        return ReviewUpdateCopy.subtitle(
            package: package.name, source: source, files: files, additions: totals.additions,
            deletions: totals.deletions)
    }

    /// What Update does, or what Update All runs; nil while nothing can be updated.
    public var footnote: String? {
        guard phase == .loaded, !isUpToDate else { return nil }
        if isAll {
            return ReviewUpdateCopy.footerAll(count: packages.count)
        }
        return ReviewUpdateCopy.footer(name: displayName ?? "", agents: agents)
    }

    /// The package's range from the selected row's `info` (`^1.2`), when that `info` is of this package.
    public var allowedRange: String? {
        guard let detailInfo, detailInfo.package == package else { return nil }
        return DetailOverviewCopy.allowedRange(why: detailInfo.why)
    }

    /// The up-to-date state's title and body.
    public var upToDateTitle: String {
        displayName.map(ReviewUpdateCopy.upToDateTitle) ?? ReviewUpdateCopy.upToDateAllTitle
    }

    public var upToDateBody: String {
        guard let displayName else { return ReviewUpdateCopy.upToDateAllBody }
        return ReviewUpdateCopy.upToDateBody(name: displayName, version: entry?.version, range: allowedRange)
    }

    /// `Couldn’t fetch the changes for 1.4.0`.
    public var fetchFailedTitle: String {
        guard let displayName else { return ReviewUpdateCopy.fetchFailedAll }
        return ReviewUpdateCopy.fetchFailed(version: offeredVersion, name: displayName)
    }

    /// The CLI's sentence, what to do, and that nothing changed.
    public func fetchFailedBody(_ message: UserMessage) -> String {
        var parts = [message.reason ?? message.title, message.action].compactMap { $0 }
        if let displayName {
            parts.append(ReviewUpdateCopy.nothingChanged(name: displayName, version: entry?.version))
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Update

    /// `update -- <the reviewed packages>`: one call, also for Update All, so it updates exactly what was shown.
    public var updateCommand: Invocation.Command {
        .update(packages: packages.map(\.name))
    }

    /// The run's title in the sheet and in Activity: `Updating pdf to 1.4.0…`, `Updating 2 packages…`.
    public var runTitle: String {
        if !isAll, let first = packages.first {
            return ReviewUpdateCopy.updating(name(of: first.name), to: first.to)
        }
        return ReviewUpdateCopy.updatingAll(packages.count)
    }

    /// The toast: `Updated pdf to 1.4.0`, `Updated pdf and review-pr`.
    public var outcomeText: String {
        if !isAll, let first = packages.first {
            return OutcomeCopy.updated(name(of: first.name), to: first.to)
        }
        return ReviewUpdateCopy.updatedAll(packages.map { name(of: $0.name) })
    }

    /// Starts Update in `run`: nothing when there is nothing to update. On exit 0 `onSuccess` closes the sheet.
    @discardableResult public func update(
        with run: SheetRun, in store: ScopeStore, runner: ActionRunner, onSuccess: @escaping @MainActor () -> Void
    ) -> Task<Void, Never>? {
        guard phase == .loaded, !packages.isEmpty else { return nil }
        let toast = outcomeText
        return run.start(
            updateCommand, title: runTitle, failure: ReviewUpdateCopy.couldNotUpdate(displayName),
            outcome: { _ in toast }, in: store, runner: runner, onSuccess: onSuccess)
    }
}
