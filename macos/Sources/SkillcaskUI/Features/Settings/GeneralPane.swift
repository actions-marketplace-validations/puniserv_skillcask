import SkillcaskCore
import SwiftUI

/// Settings › General (Settings board, left window): the command-line tool in use with Choose… and "Use the
/// detected one", Open at launch, the recent projects with Clear Recent, and the privacy line.
struct GeneralPane: View {
    /// The tool line: where the binary is, its version, and whether Settings chose it.
    struct Tool: Hashable {
        let path: String
        let version: Version?
        let configured: Bool
    }

    @Environment(AppStore.self) private var app
    @Environment(SettingsStore.self) private var settings
    /// Stands in for the located binary: the fixture boot never locates one, so previews pass the board's.
    var toolOverride: Tool?
    @State private var chooseFailure: UserMessage?

    /// What `app` located, nil before a binary was found.
    static func tool(of app: AppStore) -> Tool? {
        guard let binary = app.binary else { return nil }
        let configured = if case .configured = binary { true } else { false }
        return Tool(path: binary.url.path, version: app.capabilities?.version, configured: configured)
    }

    var body: some View {
        @Bindable var settings = settings
        SettingsPane {
            SettingsGroup {
                SettingsRow(label: SettingsCopy.commandLineTool) {
                    toolColumn
                }
                SettingsSeparator()
                SettingsRow(label: SettingsCopy.openAtLaunch) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Picker(SettingsCopy.openAtLaunch, selection: $settings.openAtLaunch) {
                            Text(SettingsCopy.lastScopeUsed).tag(SettingsStore.OpenAtLaunch.lastScope)
                            Text(ShellCopy.personalScope).tag(SettingsStore.OpenAtLaunch.personal)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                        SettingsCaption(SettingsCopy.openAtLaunchNote)
                    }
                }
            }
            SettingsGroup {
                SettingsRow(label: SettingsCopy.recentProjects, alignment: .top) {
                    recents
                }
            }
            SettingsCaption(SettingsCopy.privacy)
        }
    }

    private var tool: Tool? {
        toolOverride ?? Self.tool(of: app)
    }

    @ViewBuilder private var toolColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Text(tool?.path ?? SettingsCopy.toolNotFound)
                    .font(tool == nil ? Font.Token.body : Font.Token.mono)
                    .foregroundStyle(tool == nil ? Color.textSecondary : Color.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(SettingsCopy.choose, action: choose)
                    .controlSize(.small)
                    .disabled(!app.canChangeBinary)
            }
            if let tool, let version = tool.version {
                HStack(spacing: 0) {
                    SettingsCaption(SettingsCopy.toolLine(version: version, configured: tool.configured))
                    if tool.configured {
                        SettingsCaption(" · ")
                        Button(SettingsCopy.useDetected) {
                            Task { await app.useDetectedBinary() }
                        }
                        .buttonStyle(.link)
                        .font(Font.Token.captionMedium)
                        .foregroundStyle(app.canChangeBinary ? Color.accent : Color.textTertiary)
                        .disabled(!app.canChangeBinary)
                    }
                }
            }
            if !app.canChangeBinary {
                SettingsCaption(SettingsCopy.closeSheetFirst)
            }
            if let chooseFailure {
                MessageStrip(.error, text: chooseFailure.title, density: .compact)
            }
        }
    }

    @ViewBuilder private var recents: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(app.projects) { item in
                HStack(spacing: Spacing.inline) {
                    Text(item.name)
                        .font(Font.Token.calloutMedium)
                        .foregroundStyle(Color.textPrimary)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(Font.Token.monoSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            Button(SettingsCopy.clearRecent, action: clearRecent)
                .controlSize(.small)
                .disabled(app.projects.isEmpty || app.presentation != nil)
                .padding(.top, Spacing.xs)
        }
    }

    // MARK: - Actions

    private func choose() {
        guard let url = Workspace.chooseFile(prompt: SettingsCopy.chooseTool) else { return }
        chooseFailure = nil
        Task {
            if let error = await app.locate(executable: url) {
                chooseFailure = ErrorCopy.message(for: error)
            }
        }
    }

    /// Empties the recents through the sidebar's own removal, so stores and the selection follow; disabled while a
    /// sheet is up (the project it is pinned to could not go).
    private func clearRecent() {
        for item in app.projects {
            app.removeFromSidebar(item.scope)
        }
    }
}
