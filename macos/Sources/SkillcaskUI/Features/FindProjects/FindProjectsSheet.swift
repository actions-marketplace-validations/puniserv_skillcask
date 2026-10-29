import Foundation
import SkillcaskCore
import SwiftUI

/// Find Projects in Folder… (Flow-F1 step 4): runs `projects --json -- <root>`, then lists the folders it
/// found as a checklist, every new one ticked; Add adds the ticked ones to the sidebar and selects the first
/// (`AppStore.open(folders:)`). Folders the sidebar already lists stay ticked and disabled with "In the sidebar".
/// No hit says so; a failure shows the failure banner in place, with Retry when the error allows it.
///
/// The board draws only the step's mini panel, so the layout borrows the Adopt sheet's (header, checklist rows,
/// grouped footer) at `size`, and every word is invented (`FindProjectsCopy`).
struct FindProjectsSheet: View {
    /// What the sheet shows.
    enum Phase: Hashable {
        case loading
        case found(FindProjectsPlan)
        case failed(CLIError)
    }

    let root: URL
    let onClose: () -> Void

    @Environment(AppStore.self) private var app
    @State private var phase: Phase
    /// The ticked rows; nil until the user changes one, so the default follows the plan.
    @State private var selection: Set<URL>?

    /// Invented: the Adopt sheet's width, a little taller for a checklist of folders.
    nonisolated static let size = CGSize(width: 592, height: 380)
    /// The checklist row's leading checkbox column (Adopt `.li` 22 px).
    static let checkColumn: CGFloat = 22

    /// Runs `projects` on appear; false when a preview injected the phase.
    private let loadsOnAppear: Bool

    /// - Parameter phase: Previews only: the phase to show, `.loading` included; no command runs.
    init(root: URL, onClose: @escaping () -> Void, phase: Phase? = nil) {
        self.root = root
        self.onClose = onClose
        loadsOnAppear = phase == nil
        _phase = State(initialValue: phase ?? .loading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color.surfaceWindow)
        .task {
            if loadsOnAppear, phase == .loading {
                await load()
            }
        }
    }

    // MARK: - Derived

    private var path: String {
        AppStore.subtitle(of: root)
    }

    private var plan: FindProjectsPlan? {
        if case .found(let plan) = phase { plan } else { nil }
    }

    private var selected: Set<URL> {
        selection ?? plan?.defaultSelection ?? []
    }

    private var chosen: [URL] {
        plan?.chosen(selected) ?? []
    }

    // MARK: - Header

    /// The Adopt sheet's `.sh`: the 15 pt title and the 12 pt sentence.
    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(FindProjectsCopy.title(folder: AppStore.name(of: root)))
                .font(Font.Token.headline)
                .foregroundStyle(Color.textPrimary)
            sentence
                .font(Font.Token.callout)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.m)
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.cardGap)
    }

    @ViewBuilder private var sentence: some View {
        switch phase {
        case .loading:
            Spinner(label: FindProjectsCopy.looking(in: path))
        case .found(let plan) where plan.isEmpty:
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(FindProjectsCopy.noneFound(in: path))
                Text(FindProjectsCopy.noneFoundHint)
            }
        case .found(let plan) where plan.isAllAdded:
            Text(FindProjectsCopy.allAdded(plan.rows.count, in: path))
        case .found(let plan):
            Text(FindProjectsCopy.found(plan.rows.count, in: path))
        case .failed:
            EmptyView()
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            Color.clear
        case .failed(let error):
            FailureBanner(
                ErrorCopy.message(for: error, title: FindProjectsCopy.couldNotFind),
                onRetry: { Task { await load() } }
            )
            .padding(.horizontal, Spacing.l)
        case .found(let plan):
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(plan.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            separator
                        }
                        checklistRow(row)
                    }
                }
                .padding(.horizontal, Spacing.l)
            }
        }
    }

    /// The Adopt sheet's `.li`: the checkbox, the folder's name, its path in mono, the trailing mark.
    private func checklistRow(_ row: FindProjectsPlan.Row) -> some View {
        HStack(spacing: Spacing.rowGap) {
            Toggle(row.name, isOn: binding(for: row))
                .toggleStyle(.checkbox)
                .tint(Color.accent)
                .labelsHidden()
                .disabled(row.isAdded)
                .frame(width: Self.checkColumn, alignment: .leading)
            Text(row.name)
                .font(Font.Token.calloutMedium)
                .foregroundStyle(row.isAdded ? Color.textSecondary : Color.textPrimary)
                .lineLimit(1)
            Text(row.path)
                .font(Font.Token.monoSmall)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if row.isAdded {
                Text(FindProjectsCopy.inSidebar)
                    .font(Font.Token.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, Spacing.inline)
        .accessibilityElement(children: .combine)
    }

    private func binding(for row: FindProjectsPlan.Row) -> Binding<Bool> {
        Binding(
            get: { row.isAdded || selected.contains(row.url) },
            set: { isOn in
                var next = selected
                if isOn { next.insert(row.url) } else { next.remove(row.url) }
                selection = next
            })
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.separator)
            .frame(height: Size.hairline)
    }

    // MARK: - Footer

    /// The Adopt sheet's `.sf`: Cancel (Close once there is nothing to add) and Add on the grouped surface.
    private var footer: some View {
        VStack(spacing: 0) {
            separator
            HStack(spacing: Spacing.s) {
                Spacer(minLength: Spacing.s)
                Button(showsAdd ? SheetCopy.cancel : AdoptCopy.close, action: onClose)
                    .keyboardShortcut(.cancelAction)
                if showsAdd {
                    Button(action: add) {
                        Text(FindProjectsCopy.add(count: max(chosen.count, 1))).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
                }
            }
            .padding(.vertical, Spacing.cardGap)
            .padding(.horizontal, Spacing.l)
            .background(Color.surfaceGrouped)
        }
    }

    /// Add is offered (disabled until something is ticked) while loading and over a checklist with a folder not yet
    /// in the sidebar; not when nothing was found, every folder is already listed, or the command failed (Close).
    private var showsAdd: Bool {
        switch phase {
        case .loading: true
        case .found(let plan): !plan.isEmpty && !plan.isAllAdded
        case .failed: false
        }
    }

    // MARK: - Actions

    private func load() async {
        phase = .loading
        switch await app.projects(under: root) {
        case .success(let found):
            phase = .found(FindProjectsPlan(found: found, recents: app.settings.recentProjects))
        case .failure(.cancelled):
            break
        case .failure(let error):
            phase = .failed(error)
        }
    }

    private func add() {
        let folders = chosen
        guard !folders.isEmpty else { return }
        app.open(folders: folders)
        onClose()
    }
}
