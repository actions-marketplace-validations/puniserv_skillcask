import SkillcaskCore
import SwiftUI

/// Settings › Updates (Settings-States board, left window): the `Skillcask app` group (U5, D51) while the update check
/// is on, then check-on-open, the GitHub sign-in state with the rate
/// limit note, and the token field.
///
/// The token lives only in this view's `token` while it is typed: Save copies it into the `auth set` run's stdin,
/// empties the field before the run starts, and the field is emptied again when the tab goes away. It is never
/// shown (`SecureField`), stored, logged or put in a message.
struct UpdatesPane: View {
    @Environment(AppStore.self) private var app
    @Environment(SettingsStore.self) private var settings
    @State private var token: String
    @FocusState private var tokenFocused: Bool

    /// - Parameter token: What the field starts with; previews pass a fake to draw the dots, the app nothing.
    init(token: String = "") {
        _token = State(initialValue: token)
    }

    var body: some View {
        @Bindable var settings = settings
        SettingsPane {
            AppUpdateGroup()
            SettingsGroup {
                SettingsRow(label: SettingsCopy.checkOnOpen, alignment: .top) {
                    HStack(alignment: .top, spacing: Spacing.cardGap) {
                        Toggle(SettingsCopy.checkOnOpen, isOn: $settings.checkUpdatesOnOpen)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .tint(Color.accent)
                        SettingsNote(SettingsCopy.checkOnOpenNote)
                    }
                }
                SettingsSeparator()
                SettingsRow(label: SettingsCopy.gitHub, alignment: .top) {
                    gitHubColumn
                }
            }
            if store.gitHub != .signedIn {
                SettingsGroup {
                    SettingsRow(label: SettingsCopy.gitHubToken, alignment: .top) {
                        tokenColumn
                    }
                }
            }
        }
        .onDisappear { token = "" }
    }

    private var store: CLISettingsStore {
        app.cliSettings
    }

    private var stateLabel: String {
        switch store.gitHub {
        case .unknown: SettingsCopy.gitHubUnknown
        case .signedIn: SettingsCopy.gitHubSignedIn
        case .signedOut: SettingsCopy.signedOut
        }
    }

    @ViewBuilder private var gitHubColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.inline) {
            HStack(spacing: Spacing.s) {
                Text(stateLabel)
                    .font(Font.Token.body)
                    .foregroundStyle(Color.textPrimary)
                if store.gitHub == .signedIn {
                    Button(SettingsCopy.signOut, action: signOut)
                        .controlSize(.small)
                        .disabled(app.cliContext == nil || store.isChangingToken)
                } else {
                    Button(SettingsCopy.signIn) { tokenFocused = true }
                        .controlSize(.small)
                }
                if store.isChangingToken {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            switch store.gitHub {
            case .signedIn:
                SettingsCaption(
                    store.tokenStorage == .keychain ? SettingsCopy.tokenStored : SettingsCopy.tokenStoredByHelper)
                ForEach(store.tokenWarnings, id: \.self) { warning in
                    MessageStrip(.warning, text: warning, density: .compact)
                }
            case .signedOut:
                MessageStrip(
                    .warning, text: SettingsCopy.signedOutNote, symbol: Self.noteSymbol, density: .strip)
            case .unknown:
                MessageStrip(.warning, text: SettingsCopy.unknownNote, symbol: Self.noteSymbol, density: .strip)
            }
            if let failure = store.gitHubFailure {
                // Already masked by the store (`CLISettingsStore.redacting`).
                MessageStrip(
                    .error, title: failure.title, text: failure.reason ?? failure.action ?? "", density: .compact)
            }
        }
    }

    /// The board's circled exclamation mark.
    private static let noteSymbol = "exclamationmark.circle"

    @ViewBuilder private var tokenColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                SecureField(SettingsCopy.tokenPlaceholder, text: $token)
                    .textFieldStyle(.roundedBorder)
                    .font(Font.Token.callout)
                    .focused($tokenFocused)
                    .onSubmit(save)
                Button(SettingsCopy.save, action: save)
                    .controlSize(.small)
                    .disabled(!canSave)
            }
            // The board's Keychain sentence only once a Save showed the osxkeychain helper.
            SettingsCaption(store.tokenStorage == .keychain ? SettingsCopy.tokenNote : SettingsCopy.tokenNoteNeutral)
        }
    }

    private var canSave: Bool {
        app.cliContext != nil && !store.isChangingToken
            && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    /// Hands the token to `auth set` and empties the field first, whatever the outcome.
    private func save() {
        guard canSave, let context = app.cliContext else { return }
        let entered = token
        token = ""
        Task { await store.signIn(token: entered, in: context) }
    }

    private func signOut() {
        guard let context = app.cliContext else { return }
        Task { await store.signOut(in: context) }
    }
}
