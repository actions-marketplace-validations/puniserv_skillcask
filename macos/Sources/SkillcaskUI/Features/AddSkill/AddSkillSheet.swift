import SkillcaskCore
import SwiftUI

/// The Add Skill sheet (S8, F2; AddSkill and AddSkill-States boards). The header holds the title and the field
/// (a term or a source), with the sources searched under it; the body splits into the results (`ResultsColumn`)
/// and the selection's preview (`ResultPreview`); the footer says what Add writes and holds Cancel and Add.
///
/// The state lives in a `SearchStore` (search, consent, preview, rule, skills, rename) and the run in a `SheetRun`:
/// Add shows its progress in place of the body, Cancel stops it, exit 0 closes the sheet with the runner's toast
/// and selects the first new skill, and a failure stays in the preview pane with the CLI's hint as the action
/// until the field or the selection changes.
struct AddSkillSheet: View {
    /// What the previews draw in place of a live run.
    enum PreviewState: Sendable {
        /// The progress block with these lines, as if Add were running.
        case running(AddSkillProgress.Model)
        /// The failure of an Add, as if one had just ended so.
        case addFailure(UserMessage)
    }

    let store: ScopeStore
    /// Closes the sheet (`AppStore.presentedSheet = nil`).
    let onClose: () -> Void

    @Environment(ActionRunner.self) private var runner
    @State private var search: SearchStore
    /// The sheet's mutation: progress in place, Cancel while running, close on success (`SheetRun`).
    @State private var run = SheetRun()
    /// The spec of the Add whose failure is on screen; nil once the field or the selection moved on.
    @State private var failedSpec: String?
    private let previewState: PreviewState?

    /// The live sheet; `query` is the text the field starts with ("Find “…” in sources"), nil for an empty field.
    init(query: String?, store: ScopeStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        _search = State(initialValue: SearchStore(store: store, query: query))
        previewState = nil
    }

    /// Previews: a preloaded `search`, and optionally a run in flight or a failed Add.
    init(search: SearchStore, previewState: PreviewState? = nil, onClose: @escaping () -> Void = {}) {
        store = search.store
        self.onClose = onClose
        _search = State(initialValue: search)
        self.previewState = previewState
        if case .addFailure = previewState {
            _failedSpec = State(initialValue: search.selectedSpec?.base)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            Group {
                if let progress {
                    AddSkillProgress(model: progress)
                } else {
                    HStack(spacing: 0) {
                        ResultsColumn(search: search)
                        Rectangle()
                            .fill(Color.separator)
                            .frame(width: Size.hairline)
                        ResultPreview(search: search, addFailure: addFailure, onRetryAdd: add)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            hairline
            footer
        }
        .frame(width: Size.addSkillSheet.width, height: Size.addSkillSheet.height)
        .background(Color.surfaceWindow)
        .interactiveDismissDisabled(isRunning)
        .task { search.begin() }
        // Closing the sheet stops the pending search and the preview's download (the consent answer still lands).
        .onDisappear { search.end() }
        .onChange(of: search.query) { failedSpec = nil }
        .onChange(of: search.selection) { failedSpec = nil }
    }

    // MARK: - Derived

    private var isRunning: Bool {
        if case .running = previewState { return true }
        return run.isRunning
    }

    private var progress: AddSkillProgress.Model? {
        if case .running(let model) = previewState {
            return model
        }
        guard run.isRunning else { return nil }
        return run.action.map(AddSkillProgress.Model.init)
            ?? AddSkillProgress.Model(title: runTitle ?? "", startedAt: Date(), lines: [])
    }

    private var runTitle: String? {
        if case .running(let title) = run.phase { title } else { nil }
    }

    private var addFailure: UserMessage? {
        guard failedSpec != nil else { return nil }
        if case .addFailure(let message) = previewState {
            return message
        }
        return run.failure
    }

    private var addTitle: String {
        if let clash = search.clash {
            let name = search.renameTo.trimmingCharacters(in: .whitespacesAndNewlines)
            return AddSkillCopy.addAs(name.isEmpty ? clash.suggestion : name)
        }
        return AddSkillCopy.addButton(skills: search.info.map { _ in search.chosenSkills.count })
    }

    /// Add needs a loaded preview and a buildable command, and nothing running.
    private var canAdd: Bool {
        guard !isRunning, search.command != nil else { return false }
        if case .loaded = search.preview { return true }
        return false
    }

    // MARK: - Header and footer

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            Text(AddSkillCopy.title(scopeName: ShellCopy.name(of: store.scope)))
                .font(Font.Token.headline)
                .foregroundStyle(Color.textPrimary)
            if !isRunning {
                SearchField(query: $search.query)
                summary
            }
        }
        .padding(.top, Spacing.l)
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `7 results from Packagist acme GitHub · blocked by policy … Sorted by installs`, once results are in.
    @ViewBuilder private var summary: some View {
        let results = search.sortedResults
        if !results.isEmpty {
            HStack(spacing: Spacing.s) {
                Text(AddSkillCopy.resultsFrom(results.count))
                ForEach(search.repositories, id: \.name) { repository in
                    if repository.allowed {
                        Pill(source: repository.kind)
                    } else {
                        Pill(AddSkillCopy.blockedByPolicy(SourceCopy.label(repository.kind)))
                            .opacity(ResultsColumn.blockedOpacity)
                    }
                }
                if search.skillsSh == .enabled {
                    Pill(source: .skillsSh)
                }
                Spacer(minLength: Spacing.s)
                if search.isSortedByInstalls {
                    Text(AddSkillCopy.sortedByInstalls)
                }
            }
            .font(Font.Token.callout)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            if !isRunning {
                Text(store.scope.isPersonal ? AddSkillCopy.footerPersonal : AddSkillCopy.footerProject)
                    .font(Font.Token.callout)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Spacing.s)
            Button(SheetCopy.cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
            Button(addTitle, action: add)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .disabled(!canAdd)
        }
        .padding(.vertical, Spacing.m)
        .padding(.horizontal, Spacing.xl)
        .background(Color.surfaceGrouped)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.separator)
            .frame(height: Size.hairline)
    }

    // MARK: - Actions

    /// Stops the run while one is in flight, else closes the sheet.
    private func cancel() {
        if run.canCancel {
            run.cancel()
        } else {
            onClose()
        }
    }

    /// Runs `add` through the runner; on exit 0 the sheet closes and the first new skill is selected. The skill
    /// list is single-selection (`ScopeStore.selection` is one id), so the other new rows are not selected.
    private func add() {
        guard canAdd, let command = search.command, let spec = search.selectedSpec else { return }
        let toast = Self.toast(package: spec.base, skills: addedNames, version: search.info?.version)
        let first = addedNames.first
        let store = store
        failedSpec = spec.base
        run.start(
            command, title: AddSkillCopy.adding(spec.base), failure: AddSkillCopy.couldNotAdd(spec.base),
            outcome: { _ in toast }, in: store, runner: runner,
            onSuccess: {
                onClose()
                if let first {
                    Task { await store.select(first) }
                }
            })
    }

    /// The skills as agents will see them: the chosen ones, the clashing one under its new name.
    private var addedNames: [String] {
        let rename = search.clash.map { ($0.skill, search.renameTo.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return search.chosenSkills.map { name in
            if let rename, rename.0 == name, !rename.1.isEmpty { rename.1 } else { name }
        }
    }

    /// `Added jira-syntax and jira-communication (4.2.0)`; `Added <package>` when the skills are not known.
    static func toast(package: String, skills: [String], version: String?) -> String {
        guard let version, !skills.isEmpty else { return AddSkillCopy.added(package: package) }
        return OutcomeCopy.added(skills, version: version)
    }
}

/// The board's field: the magnifier, the system text field, and the source shapes at its trailing end, with the
/// accent ring while it has focus.
private struct SearchField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    /// The board's 30 pt field (`Size.search` is the list's 26 pt one).
    static let height = Size.search + Spacing.xs
    /// The focus ring's `box-shadow: 0 0 0 3px var(--accent-soft)`.
    static let ringWidth: CGFloat = 3

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
            TextField(AddSkillCopy.fieldLabel, text: $query)
                .textFieldStyle(.plain)
                .font(Font.Token.body)
                .focused($isFocused)
                .accessibilityLabel(AddSkillCopy.fieldLabel)
            HStack(spacing: Spacing.xs) {
                Text(AddSkillCopy.sourceHint)
                    .font(Font.Token.caption)
                Text(AddSkillCopy.sourceShapes)
                    .font(Font.Token.monoSmall)
            }
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.cardGap)
        .frame(height: Self.height)
        .background(Color.controlFill, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .strokeBorder(isFocused ? Color.accent : Color.controlBorder, lineWidth: Size.hairline)
        )
        .background(
            RoundedRectangle(cornerRadius: Radius.m + Self.ringWidth, style: .continuous)
                .fill(isFocused ? Color.accentSoft : Color.clear)
                .padding(-Self.ringWidth)
        )
        .onAppear { isFocused = true }
    }
}
