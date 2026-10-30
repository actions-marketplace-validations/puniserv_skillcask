import SkillcaskCore
import SkillcaskUpdates
import SwiftUI

/// Settings › Updates' `Skillcask app` group (U5, the brief's version): the installed version and how, the daily
/// check switch with its privacy line, the last check with `Check Now`, and the skipped version with `Reset`. Absent
/// while the update check is off (`swift run`, fixtures). No pre-release switch and no command-line tool line: the
/// app runs its bundled CLI, which is its own version.
struct AppUpdateGroup: View {
    @Environment(AppUpdateStore.self) private var updates

    var body: some View {
        if let installed = updates.installed {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(AppUpdateCopy.appGroup)
                    .font(Font.Token.calloutSemibold)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.leading, Spacing.xs)
                    .accessibilityAddTraits(.isHeader)
                SettingsGroup {
                    SettingsRow(label: AppUpdateCopy.installedLabel) {
                        Text(AppUpdateCopy.installedLine(installed, updates.installMethod))
                            .font(Font.Token.body)
                            .foregroundStyle(Color.textPrimary)
                            .textSelection(.enabled)
                    }
                    SettingsSeparator()
                    SettingsRow(label: AppUpdateCopy.dailyLabel, alignment: .top) {
                        dailyColumn
                    }
                    SettingsSeparator()
                    SettingsRow(label: AppUpdateCopy.lastCheckedLabel, alignment: .top) {
                        lastCheckedColumn
                    }
                    SettingsSeparator()
                    SettingsRow(label: AppUpdateCopy.skippedLabel) {
                        HStack(spacing: Spacing.s) {
                            Text(AppUpdateCopy.skipped(updates.state.skippedVersion))
                                .font(Font.Token.body)
                                .foregroundStyle(Color.textPrimary)
                            Button(AppUpdateCopy.reset) { updates.resetSkipped() }
                                .controlSize(.small)
                                .disabled(updates.state.skippedVersion == nil)
                        }
                    }
                }
            }
        }
    }

    private var dailyColumn: some View {
        @Bindable var updates = updates
        return HStack(alignment: .top, spacing: Spacing.cardGap) {
            Toggle(AppUpdateCopy.dailyLabel, isOn: $updates.dailyCheck)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Color.accent)
            SettingsNote(AppUpdateCopy.dailyNote)
        }
    }

    private var lastCheckedColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.inline) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                lastChecked
                    .font(Font.Token.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if updates.isChecking {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(AppUpdateCopy.checkNow) { Task { await updates.checkForUpdates() } }
                    .controlSize(.small)
                    .disabled(updates.isChecking || !updates.canCheck)
            }
            if let blocker = updates.checkNowBlocker {
                SettingsCaption(blocker)
            }
        }
    }

    /// `Today at 09:14 · 0.10.3 available`, the version in the warning text colour as on U5.
    private var lastChecked: Text {
        let when = Text(AppUpdateCopy.lastChecked(updates.state.lastCheckAt, now: Date()))
            .foregroundStyle(Color.textPrimary)
        guard let known = updates.knownUpdate else { return when }
        return when + Text(AppUpdateCopy.availableSuffix(known)).foregroundStyle(Color.statusWarningText)
    }
}
