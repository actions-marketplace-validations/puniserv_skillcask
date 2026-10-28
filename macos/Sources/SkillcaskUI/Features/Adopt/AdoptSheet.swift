import Foundation
import SkillcaskCore
import SkillcaskDomain
import SwiftUI

/// The Adopt sheet (S9, Adopt-States board) at `Size.adoptSheet`: one not managed skill or a batch.
///
/// - One skill with a recorded source: the source in a locked field, Change… unlocks it.
/// - One skill without a source: a text field with the three accepted shapes as its placeholder, checked by
///   `PackageSpec.validate` before Adopt enables.
/// - Several: a checklist of the rows with a source (selected), the rows without one disabled with "needs a
///   source", which narrows the sheet to that skill. Adopt runs them one at a time through `SheetRun.startBatch`:
///   each row gets its own result and duration, a failure stops the rest, Cancel stops after the current one.
///
/// Every run is `skillcask -g add --adopt -- <spec>`, which moves the current copy to the CLI's `adopted/` folder
/// (stated once with its real path) and installs the package in its place. The CLI adopts only in the personal
/// scope, so in a project the sheet says so and offers no Adopt button (`AdoptPlan.isAvailable`).
///
/// Declared deviations from the board: the green "Your copy matches v4.0.1 at that source" strip of the known
/// source is replaced by the amber "If the source’s content differs…" strip (the app cannot compare the copy with
/// the source before adopting), the note under it names no constraint or version, a finished batch row reads
/// "Adopted · copy kept" without the version and has no "your copy differed" variant (0.9.1 prints no document
/// saying either), and "Keep as Local Skill" is not offered (no CLI command does it; Cancel leaves the skill as it
/// is, which the sentence under the strip already says).
struct AdoptSheet: View {
    /// The not-managed skills to adopt: one from a row or the detail, several from the Skill menu.
    let skills: [String]
    let store: ScopeStore
    /// Closes the sheet (`AppStore.presentedSheet = nil`).
    let onClose: () -> Void

    @Environment(AppStore.self) private var app
    @Environment(ActionRunner.self) private var runner

    /// The sheet's mutation: progress in place, Cancel while running, close on success (`SheetRun`).
    @State private var run: SheetRun
    /// The batch rows ticked for adopting; starts with every row that has a source.
    @State private var selection: Set<String>?
    /// "needs a source" narrowed a batch to this skill.
    @State private var focused: String?
    /// The recorded source was unlocked with Change….
    @State private var isEditing: Bool
    /// The text of the source field.
    @State private var source: String
    /// When the batch started, for the header's elapsed time.
    @State private var startedAt: Date?
    /// "… 6 more" was pressed: the checklist lists every row.
    @State private var showsAll = false
    @FocusState private var isFieldFocused: Bool

    /// - Parameters:
    ///   - run: Previews only: a run preloaded midway.
    ///   - startedAt: Previews only: when that batch started.
    ///   - source: Previews only: text already typed in the field.
    ///   - editing: Previews only: the recorded source unlocked.
    ///   - focused: Previews only: a batch narrowed to this "needs a source" row.
    ///   - showsAll: Previews only: the checklist expanded.
    init(
        skills: [String], store: ScopeStore, onClose: @escaping () -> Void, run: SheetRun = SheetRun(),
        startedAt: Date? = nil, source: String = "", editing: Bool = false, focused: String? = nil,
        showsAll: Bool = false
    ) {
        self.skills = skills
        self.store = store
        self.onClose = onClose
        _run = State(initialValue: run)
        _startedAt = State(initialValue: startedAt)
        _source = State(initialValue: source)
        _isEditing = State(initialValue: editing || focused != nil)
        _focused = State(initialValue: focused)
        _showsAll = State(initialValue: showsAll)
    }

    /// The source field's height (board `.field { height: 28px }`).
    static let fieldHeight: CGFloat = 28
    /// The source field's corners (board `.field { border-radius: 7px }`); no 7 pt radius token exists.
    static let fieldRadius: CGFloat = 7
    /// The focus halo around the field (board `box-shadow: 0 0 0 3px var(--accent-soft)`).
    static let focusHalo: CGFloat = 3
    /// The checklist rows shown before "… N more" (the board's six).
    static let collapsedRows = 6
    /// Unknown-source rows kept in view when the checklist is collapsed (the board's two).
    static let collapsedUnknownRows = 2
    /// The batch row's columns (board `.li { grid-template-columns: 22px 150px minmax(0,1fr) 110px }`).
    static let checkColumn: CGFloat = 22
    static let nameColumn: CGFloat = 150
    static let trailingColumn: CGFloat = 110
    /// The row's state symbol (board `svg width="14"`).
    static let iconSize: CGFloat = 14
    /// The waiting dot's inset under the symbols (board `margin-left: 3px`).
    static let dotInset: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            footer
        }
        .frame(width: Size.adoptSheet.width, height: Size.adoptSheet.height)
        .background(Color.surfaceWindow)
        .interactiveDismissDisabled(!run.canClose)
    }

    // MARK: - Derived

    private var plan: AdoptPlan {
        AdoptPlan(skills: skills, entries: store.snapshot?.entries ?? [], scope: store.scope)
    }

    /// The one skill the sheet adopts: the only one asked for, or the batch row "needs a source" narrowed to.
    private var single: AdoptPlan.Item? {
        let plan = plan
        if let focused {
            return plan.items.first { $0.id == focused }
        }
        return plan.isBatch ? nil : plan.items.first
    }

    private var isBatchView: Bool {
        single == nil && plan.isBatch
    }

    private var selected: Set<String> {
        selection ?? Set(plan.known.map(\.id))
    }

    /// The selected batch rows, in plan order.
    private var selectedItems: [AdoptPlan.Item] {
        plan.known.filter { selected.contains($0.id) }
    }

    /// `~/.config/skillcask/adopted/`: the CLI's config directory as the app resolves it for the children.
    private var adoptedFolder: String {
        Self.adoptedFolder(manifest: app.manifest(of: .personal))
    }

    /// `<config>/adopted/` beside the personal `manifest` (`src/commands.rs` `adopt` moves copies to
    /// `s.config/adopted/<unix time>/`), with the home directory as `~` and a trailing `/`.
    static func adoptedFolder(manifest: URL) -> String {
        let folder = manifest.deletingLastPathComponent().appending(path: "adopted").path
        return (folder as NSString).abbreviatingWithTildeInPath + "/"
    }

    /// The spec the single skill adopts from: the field when it is open, else the recorded source.
    private func spec(for item: AdoptPlan.Item) -> Result<String, PackageSpec.Problem> {
        if let recorded = item.spec, !isEditing {
            return .success(recorded)
        }
        return PackageSpec.validate(source).map(\.text)
    }

    private var batchStarted: Bool {
        !run.items.isEmpty
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if !plan.isAvailable {
            projectGate
        } else if let single {
            singleForm(single)
        } else if isBatchView {
            if batchStarted {
                batchProgress
            } else {
                batchChecklist
            }
        } else {
            header(title: AdoptCopy.title(skills: skills), body: AdoptCopy.nothingToAdopt, mono: nil)
            Spacer(minLength: 0)
        }
    }

    /// `.sh`: `padding: 12px 16px 10px; gap: 4px`, the 15 pt title and the 12 pt sentence.
    private func header(title: String, body: String, mono: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Font.Token.headline)
                .foregroundStyle(Color.textPrimary)
            Text(Self.sentence(body, mono: mono))
                .font(Font.Token.callout)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.m)
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.cardGap)
    }

    /// The sentence with `mono` (the adopted folder) in the 11 pt mono face, as the board draws it.
    static func sentence(_ text: String, mono: String?) -> AttributedString {
        var attributed = AttributedString(text)
        if let mono, let range = attributed.range(of: mono) {
            attributed[range].font = Font.Token.monoSmall
        }
        return attributed
    }

    private var projectGate: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: AdoptCopy.projectTitle(skills: skills), body: AdoptCopy.projectBody(skills: names), mono: nil)
            Spacer(minLength: 0)
        }
    }

    /// The requested skills by name, for sentences.
    private var names: [String] {
        plan.items.isEmpty ? skills : plan.items.map(\.name)
    }

    // MARK: - Single

    private func singleForm(_ item: AdoptPlan.Item) -> some View {
        let known = item.spec != nil
        let body =
            known
            ? AdoptCopy.knownBody(skill: item.name, folder: adoptedFolder)
            : AdoptCopy.unknownBody(folder: adoptedFolder)
        return VStack(alignment: .leading, spacing: 0) {
            header(title: AdoptCopy.title(skills: [item.name]), body: body, mono: adoptedFolder)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(known ? AdoptCopy.knownLabel : AdoptCopy.sourceLabel)
                    .font(Font.Token.callout)
                    .foregroundStyle(Color.textSecondary)
                sourceField(item)
                if let failure = run.failure {
                    FailureBanner(failure)
                } else {
                    MessageStrip(.warning, text: AdoptCopy.differs, density: .sheet)
                }
                Text(known ? AdoptCopy.knownNote(skill: item.name) : AdoptCopy.keepLocal)
                    .font(Font.Token.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Spacing.xs)
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.m)
            Spacer(minLength: 0)
        }
    }

    /// The locked recorded source with Change…, or the editable field in the same box (board `.field`: 28 pt, 1 pt
    /// control border, radius 7; locked on the grouped fill, editable on the control fill), so Change… does not
    /// move anything; the problem of a typed source sits under it.
    @ViewBuilder private func sourceField(_ item: AdoptPlan.Item) -> some View {
        if let recorded = item.spec, !isEditing {
            HStack(spacing: Spacing.s) {
                fieldBox(locked: true) {
                    Text(recorded)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(AdoptCopy.knownLabel)
                .accessibilityValue(recorded)
                Button(AdoptCopy.change) {
                    source = recorded
                    isEditing = true
                    isFieldFocused = true
                }
                .disabled(run.isRunning)
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Same box as the locked field (height, border, radius), spanning the row once Change… is gone.
                fieldBox(locked: false) {
                    TextField(AdoptCopy.sourceLabel, text: $source, prompt: Text(AdoptCopy.placeholder))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .focused($isFieldFocused)
                        .disabled(run.isRunning)
                        .onSubmit(adoptSingle)
                }
                if case .failure(let problem) = spec(for: item), let text = AdoptCopy.problem(problem) {
                    Text(text)
                        .font(Font.Token.caption)
                        .foregroundStyle(Color.statusErrorText)
                }
            }
        }
    }

    /// The board's `.field` box around `content`, in mono 12 pt; the editable one draws the accent border and halo
    /// while focused (board `border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft)`).
    private func fieldBox<Content: View>(locked: Bool, @ViewBuilder content: () -> Content) -> some View {
        let focused = !locked && isFieldFocused
        let shape = RoundedRectangle(cornerRadius: Self.fieldRadius, style: .continuous)
        return content()
            .font(Font.Token.mono)
            .padding(.horizontal, Spacing.cardGap)
            .frame(maxWidth: .infinity, minHeight: Self.fieldHeight, maxHeight: Self.fieldHeight, alignment: .leading)
            .background(locked ? Color.surfaceGrouped : Color.controlFill, in: shape)
            .overlay(shape.strokeBorder(focused ? Color.accent : Color.controlBorder, lineWidth: Size.hairline))
            .background(
                shape.inset(by: -Self.focusHalo).fill(focused ? Color.accentSoft : Color.clear)
            )
    }

    // MARK: - Batch

    private var batchChecklist: some View {
        let plan = plan
        return VStack(alignment: .leading, spacing: 0) {
            header(
                title: AdoptCopy.title(skills: plan.items.map(\.name)),
                body: AdoptCopy.batchBody(known: plan.known.count, unknown: plan.unknown.count, folder: adoptedFolder),
                mono: adoptedFolder)
            if let failure = run.failure {
                // A batch that could not start (another command runs) says so above the checklist.
                FailureBanner(failure)
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.s)
            }
            let listing = Self.listing(known: plan.known, unknown: plan.unknown, showsAll: showsAll)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(listing.rows.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            separator
                        }
                        checklistRow(item)
                    }
                    if listing.hidden > 0 {
                        Button(AdoptCopy.more(listing.hidden)) { showsAll = true }
                            .buttonStyle(.plain)
                            .font(Font.Token.caption)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.vertical, Spacing.inline)
                    }
                }
                .padding(.horizontal, Spacing.l)
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// The checklist as the board lists it: the first rows with a source, then (up to two) rows that need one, so
    /// "needs a source" is always in view, and the rest behind "… N more"; every row when `showsAll`.
    static func listing(
        known: [AdoptPlan.Item], unknown: [AdoptPlan.Item], showsAll: Bool
    ) -> (
        rows: [AdoptPlan.Item], hidden: Int
    ) {
        let all = known + unknown
        guard !showsAll, all.count > collapsedRows + 1 else { return (all, 0) }
        let unknownShown = min(unknown.count, collapsedUnknownRows)
        let knownShown = min(known.count, collapsedRows - unknownShown)
        let rows = Array(known.prefix(knownShown)) + Array(unknown.prefix(unknownShown))
        return (rows, all.count - rows.count)
    }

    /// `.li`: `22px 150px 1fr 110px`, `gap: 10px`, `padding: 6px 0`.
    private func checklistRow(_ item: AdoptPlan.Item) -> some View {
        AdoptRow(dimmed: !item.hasSource) {
            Toggle(item.name, isOn: binding(for: item))
                .toggleStyle(.checkbox)
                .tint(Color.accent)
                .labelsHidden()
                .disabled(!item.hasSource)
        } name: {
            Text(item.name)
        } detail: {
            if let spec = item.spec {
                Text(spec)
                    .font(Font.Token.monoSmall)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(AdoptCopy.sourceUnknown)
                    .font(Font.Token.callout)
            }
        } trailing: {
            if item.hasSource {
                Text(item.version ?? "")
                    .font(Font.Token.caption)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Button(AdoptCopy.needsSource) {
                    focused = item.id
                    source = ""
                    isEditing = true
                    run = SheetRun()
                }
                .buttonStyle(.link)
                .font(Font.Token.calloutMedium)
                .foregroundStyle(Color.accent)
            }
        }
    }

    private func binding(for item: AdoptPlan.Item) -> Binding<Bool> {
        Binding(
            get: { selected.contains(item.id) },
            set: { isOn in
                var next = selected
                if isOn { next.insert(item.id) } else { next.remove(item.id) }
                selection = next
            })
    }

    private var batchProgress: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.cardGap) {
                if run.isRunning {
                    ProgressView().controlSize(.small)
                }
                Text(progressTitle)
                    .font(Font.Token.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s)
                if let startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(AdoptCopy.elapsed(context.date.timeIntervalSince(startedAt)))
                            .font(Font.Token.caption)
                            .foregroundStyle(Color.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.top, Spacing.m)
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.cardGap)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(run.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            separator
                        }
                        progressRow(item)
                    }
                }
                .padding(.horizontal, Spacing.l)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var progressTitle: String {
        let count = run.items.count
        if run.isRunning {
            let current = run.items.firstIndex { $0.state == .running }.map { $0 + 1 } ?? run.doneCount
            return AdoptCopy.batchProgress(count: count, current: current)
        }
        if case .failed = run.phase {
            return AdoptCopy.ended(done: run.doneCount, of: count, failed: true)
        }
        if case .stopped = run.phase {
            return AdoptCopy.ended(done: run.doneCount, of: count, failed: false)
        }
        return AdoptCopy.batchProgress(count: count, current: run.doneCount)
    }

    private func progressRow(_ item: SheetRun.Item) -> some View {
        let dimmed: Bool
        switch item.state {
        case .waiting, .skipped: dimmed = true
        default: dimmed = false
        }
        return AdoptRow(dimmed: dimmed, nameWeight: !dimmed) {
            AdoptStateIcon(state: item.state)
        } name: {
            Text(name(of: item.id))
        } detail: {
            progressDetail(item)
        } trailing: {
            switch item.state {
            case .done(let duration), .failed(_, let duration):
                Text(AdoptCopy.duration(duration))
                    .font(Font.Token.caption)
                    .foregroundStyle(Color.textSecondary)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder private func progressDetail(_ item: SheetRun.Item) -> some View {
        switch item.state {
        case .waiting:
            Text(AdoptCopy.waiting)
        case .running:
            Text(run.action?.lines.last?.text ?? AdoptCopy.adoptingFallback)
                .foregroundStyle(Color.textSecondary)
        case .done:
            Text(AdoptCopy.adoptedItem)
                .foregroundStyle(Color.textSecondary)
        case .failed(let message, _):
            Text(message.reason ?? message.title)
                .foregroundStyle(Color.statusErrorText)
        case .skipped:
            Text(AdoptCopy.notRun)
        }
    }

    private func name(of id: String) -> String {
        plan.items.first { $0.id == id }?.name ?? id
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.separator)
            .frame(height: Size.hairline)
    }

    // MARK: - Footer

    /// `.sf`: `padding: 10px 16px`, a hairline above, the grouped surface; the note on the left, Cancel and the
    /// primary button on the right.
    private var footer: some View {
        VStack(spacing: 0) {
            separator
            HStack(spacing: Spacing.s) {
                if focused != nil {
                    Button(AdoptCopy.back, action: backToBatch)
                        .disabled(run.isRunning)
                }
                footerNote
                Spacer(minLength: Spacing.s)
                Button(cancelTitle, action: cancel)
                    .keyboardShortcut(.cancelAction)
                if plan.isAvailable, single != nil || isBatchView {
                    primaryButton
                }
            }
            .padding(.vertical, Spacing.cardGap)
            .padding(.horizontal, Spacing.l)
            .background(Color.surfaceGrouped)
        }
    }

    @ViewBuilder private var footerNote: some View {
        if isBatchView, plan.isAvailable {
            Text(batchStarted && run.isRunning ? AdoptCopy.cancelStopsAfterCurrent : AdoptCopy.runsOneAtATime)
                .font(Font.Token.callout)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
        } else if single != nil, let action = run.action {
            Spinner(label: action.lines.last?.text ?? action.title)
        }
    }

    private var primaryButton: some View {
        Button {
            if isBatchView { adoptBatch() } else { adoptSingle() }
        } label: {
            Text(primaryTitle).fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.accent)
        .keyboardShortcut(.defaultAction)
        .disabled(!canAdopt)
    }

    private var primaryTitle: String {
        guard isBatchView else { return AdoptCopy.adopt(count: nil) }
        return AdoptCopy.adopt(count: batchStarted ? run.items.count : selectedItems.count)
    }

    private var cancelTitle: String {
        isBatchView && batchStarted && !run.isRunning ? AdoptCopy.close : SheetCopy.cancel
    }

    private var canAdopt: Bool {
        guard !run.isRunning, !runner.isRunning else { return false }
        if isBatchView {
            return !batchStarted && !selectedItems.isEmpty
        }
        guard let single, case .success = spec(for: single) else { return false }
        return true
    }

    // MARK: - Actions

    private func adoptSingle() {
        guard canAdopt, let single, case .success(let typed) = spec(for: single),
            let command = AdoptPlan.command(spec: typed, scope: store.scope)
        else { return }
        let name = single.name
        // Narrowed from the batch: success returns to the batch (its row is then managed and leaves the list).
        let narrowed = focused != nil
        run.start(
            command, title: AdoptCopy.running(name), failure: AdoptCopy.couldNotAdopt(name),
            outcome: { AdoptCopy.adopted(name, scope: $0) }, in: store, runner: runner,
            onSuccess: { if narrowed { backToBatch() } else { onClose() } })
    }

    private func adoptBatch() {
        guard canAdopt else { return }
        let items = selectedItems
        let scope = store.scope
        var commands: [String: Invocation.Command] = [:]
        var names: [String: String] = [:]
        for item in items {
            names[item.id] = item.name
            if let spec = item.spec, let command = AdoptPlan.command(spec: spec, scope: scope) {
                commands[item.id] = command
            }
        }
        startedAt = Date()
        run.startBatch(
            items.map(\.id), title: AdoptCopy.runningBatch(count: items.count),
            failure: AdoptCopy.couldNotAdoptBatch(count: items.count),
            // Every selected row has a command; an empty spec would fail that row's invocation, never run `add`.
            command: { commands[$0] ?? .add(spec: "", repository: nil, adopt: true, rename: [:], skills: []) },
            itemTitle: { AdoptCopy.running(names[$0] ?? $0) },
            itemFailure: { AdoptCopy.couldNotAdopt(names[$0] ?? $0) },
            summary: { AdoptCopy.summary(done: $0, scope: $1) }, in: store, runner: runner, onSuccess: { onClose() })
    }

    /// Leaves the "needs a source" row and shows the batch checklist again, with a fresh run.
    private func backToBatch() {
        focused = nil
        isEditing = false
        source = ""
        run = SheetRun()
    }

    /// Stops the run while one is in flight, else closes the sheet.
    private func cancel() {
        if run.canCancel {
            run.cancel()
        } else {
            onClose()
        }
    }
}

/// One `.li` row of the batch: the leading control, the name, the source or result, the trailing slot.
private struct AdoptRow<Leading: View, Name: View, Detail: View, Trailing: View>: View {
    let dimmed: Bool
    var nameWeight = true
    @ViewBuilder let leading: Leading
    @ViewBuilder let name: Name
    @ViewBuilder let detail: Detail
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.rowGap) {
            leading
                .frame(width: AdoptSheet.checkColumn, alignment: .leading)
            name
                .font(nameWeight ? Font.Token.calloutMedium : Font.Token.callout)
                .lineLimit(1)
                .frame(width: AdoptSheet.nameColumn, alignment: .leading)
            detail
                .font(Font.Token.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .frame(width: AdoptSheet.trailingColumn, alignment: .trailing)
        }
        .foregroundStyle(dimmed ? Color.textSecondary : Color.textPrimary)
        .padding(.vertical, Spacing.inline)
    }
}

/// The leading mark of a batch row: the ok check, the system spinner, the waiting dot, the error cross.
private struct AdoptStateIcon: View {
    let state: SheetRun.Item.State

    var body: some View {
        switch state {
        case .waiting, .skipped:
            StatusDot(.neutral)
                .padding(.leading, AdoptSheet.dotInset)
        case .running:
            ProgressView().controlSize(.mini)
        case .done:
            symbol("checkmark.circle", Color.statusOkText)
        case .failed:
            symbol("xmark.circle", Color.statusErrorText)
        }
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: AdoptSheet.iconSize, height: AdoptSheet.iconSize)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
