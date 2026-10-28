import SkillcaskCore
import SwiftUI

/// Settings › Advanced (Settings-States board, right window): the environment table every new run gets (through
/// `AppStore.setEnvironmentVariables`, which applies only the names `EnvironmentPolicy` allows), the config.toml and
/// adopted-copies folders the CLI uses in that environment, Activity, and the policy footnote.
///
/// Declared differences from the Settings-States board: the table is the native bordered `Table`, so its header
/// background, separators and column dividers are the system's rather than the board's `--win` header; the Name
/// column is `Size.settingsLabel` (200 pt) where the board draws 220.
struct AdvancedPane: View {
    typealias Variable = SettingsStore.EnvironmentVariable

    @Environment(AppStore.self) private var app
    @Environment(SettingsStore.self) private var settings
    @Environment(ActionRunner.self) private var runner
    @Environment(\.openWindow) private var openWindow
    /// Stands in for the measured adopted folder: previews pass the board's summary.
    var adoptedOverride: String?
    @State private var adoptedSummary: String?

    var body: some View {
        SettingsPane {
            SettingsGroup(padded: false) {
                environmentTable
            }
            SettingsGroup {
                SettingsRow(label: SettingsCopy.configurationFile) {
                    HStack(spacing: Spacing.s) {
                        monoPath(configFile)
                        Button(SettingsCopy.openConfig) { Workspace.openOrReveal(configFile) }
                            .controlSize(.small)
                            .fixedSize()
                    }
                }
                SettingsSeparator()
                SettingsRow(label: SettingsCopy.adoptedCopies) {
                    // The board's one line does not fit 600 pt with the real path: the summary goes under it.
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.s) {
                            monoPath(adoptedFolder)
                            Button(SettingsCopy.revealInFinder) { Workspace.openOrReveal(adoptedFolder) }
                                .controlSize(.small)
                                .fixedSize()
                        }
                        SettingsCaption(adoptedOverride ?? adoptedSummary ?? SettingsCopy.noAdopted)
                    }
                }
                SettingsSeparator()
                SettingsRow(label: SettingsCopy.activity) {
                    HStack(spacing: Spacing.s) {
                        // Opens the drawer under the list of the main window (S15); ⌥⌘L there toggles it.
                        Button(SettingsCopy.showActivity) {
                            runner.isActivityShown = true
                            if !Workspace.bringMainWindowForward() {
                                openWindow(id: MainWindow.sceneID)
                            }
                        }
                        .controlSize(.small)
                        SettingsCaption(SettingsCopy.activityNote)
                    }
                }
            }
            SettingsCaption(SettingsCopy.policyNote)
        }
        // A value still being edited when the window closes is committed then (names were saved as typed).
        .onDisappear { settings.commitEnvironmentValues() }
        .task(id: adoptedFolder) {
            guard adoptedOverride == nil else { return }
            adoptedSummary = await Self.summary(of: adoptedFolder)
        }
    }

    // MARK: - Environment table

    @ViewBuilder private var environmentTable: some View {
        Text(SettingsCopy.environmentTitle)
            .font(Font.Token.bodyEmphasis)
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Size.cardPaddingH)
            .padding(.top, Spacing.rowGap)
            .padding(.bottom, Spacing.inline)
        Table(settings.environmentVariables) {
            TableColumn(SettingsCopy.name) { row in
                HStack(spacing: Spacing.xs) {
                    cell(row.id, \.name)
                    if !row.name.isEmpty && !row.isAllowed {
                        Image(systemName: Self.refusedSymbol)
                            .foregroundStyle(Color.statusWarningText)
                            .help(SettingsCopy.refusedVariable)
                            .accessibilityLabel(SettingsCopy.refusedVariable)
                    }
                }
            }
            .width(Size.settingsLabel)
            TableColumn(SettingsCopy.value) { row in
                MaskedCell(text: binding(row.id, \.value), onCommit: settings.commitEnvironmentValues)
            }
            TableColumn("") { row in
                Button(SettingsCopy.minus) { remove(row.id) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(SettingsCopy.removeVariable(row.name))
                    .help(SettingsCopy.removeVariable(row.name))
            }
            .width(Size.settingsRemoveColumn)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: false))
        .frame(height: tableHeight)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Button(SettingsCopy.addVariable, action: add)
                    .controlSize(.small)
                SettingsCaption(SettingsCopy.environmentNote)
            }
            if settings.environmentVariables.contains(where: { !$0.name.isEmpty && !$0.isAllowed }) {
                MessageStrip(.warning, text: SettingsCopy.refusedVariable, density: .compact)
            }
            if settings.environmentVariables.contains(where: \.hasCredentials) {
                MessageStrip(.warning, text: SettingsCopy.credentialsNotSaved, density: .compact)
            }
        }
        .padding(.horizontal, Size.cardPaddingH)
        .padding(.vertical, Spacing.s)
    }

    private static let refusedSymbol = "exclamationmark.triangle"

    /// Header plus the rows, at least two rows tall so an empty table still reads as one.
    private var tableHeight: CGFloat {
        CGFloat(max(settings.environmentVariables.count, 2) + 1) * Size.settingsTableRow
    }

    private func cell(_ id: Variable.ID, _ field: WritableKeyPath<Variable, String>) -> some View {
        TextField("", text: binding(id, field))
            .textFieldStyle(.plain)
            .font(Font.Token.monoSmall)
            .foregroundStyle(Color.textPrimary)
    }

    private func binding(_ id: Variable.ID, _ field: WritableKeyPath<Variable, String>) -> Binding<String> {
        Binding(
            get: { settings.environmentVariables.first { $0.id == id }?[keyPath: field] ?? "" },
            set: { update(id, field, to: $0) })
    }

    private func monoPath(_ url: URL) -> some View {
        let path = (url.path as NSString).abbreviatingWithTildeInPath + (url.hasDirectoryPath ? "/" : "")
        return Text(path)
            .font(Font.Token.mono)
            .foregroundStyle(Color.textPrimary)
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)
            .help(path)
    }

    // MARK: - Paths

    private var configFile: URL {
        app.configFile()
    }

    private var adoptedFolder: URL {
        configFile.deletingLastPathComponent().appending(path: "adopted", directoryHint: .isDirectory)
    }

    /// `4 folders · 1.2 MB` for the folders under `folder`, off the main actor; nil when it does not exist.
    static func summary(of folder: URL) async -> String? {
        await Task.detached { measure(folder) }.value
    }

    private nonisolated static func measure(_ folder: URL) -> String? {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        else { return nil }
        let folders = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        var bytes: Int64 = 0
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let walk = manager.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) {
            for case let url as URL in walk {
                let values = try? url.resourceValues(forKeys: keys)
                if values?.isRegularFile == true {
                    bytes += Int64(values?.totalFileAllocatedSize ?? 0)
                }
            }
        }
        return SettingsCopy.adoptedSummary(folders: folders.count, bytes: bytes)
    }

    // MARK: - Actions

    private func add() {
        app.setEnvironmentVariables(settings.environmentVariables + [Variable(name: "", value: "")])
    }

    private func remove(_ id: Variable.ID) {
        app.setEnvironmentVariables(settings.environmentVariables.filter { $0.id != id })
    }

    private func update(_ id: Variable.ID, _ field: WritableKeyPath<Variable, String>, to value: String) {
        var rows = settings.environmentVariables
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index][keyPath: field] = value
        app.setEnvironmentVariables(rows)
    }
}

/// A value cell that shows URL userinfo and token-shaped parts masked (`EnvironmentPolicy.masked`) until it is
/// focused for editing; the field underneath stays clickable. While masked, the field is hidden from accessibility
/// and the visible text carries the masked value, so VoiceOver never reads the clear one. Ending the edit (focus
/// loss or Return) calls `onCommit`, the only point at which a value may be saved.
private struct MaskedCell: View {
    @Binding var text: String
    let onCommit: () -> Void
    @FocusState private var focused: Bool

    private var showsMask: Bool {
        !focused && EnvironmentPolicy.hasCredentials(text)
    }

    private var masked: String {
        EnvironmentPolicy.masked(text, mask: SettingsCopy.redacted)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(onCommit)
                .opacity(showsMask ? 0 : 1)
                .accessibilityHidden(showsMask)
            if showsMask {
                Text(masked)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                    .accessibilityLabel(SettingsCopy.value)
                    .accessibilityValue(masked)
            }
        }
        .font(Font.Token.monoSmall)
        .foregroundStyle(Color.textPrimary)
        .onChange(of: focused) { _, isFocused in
            if !isFocused {
                onCommit()
            }
        }
    }
}
