import AppKit
import SkillcaskCore
import SwiftUI

/// The S13 onboarding sheet (Onboarding board: CLI missing; Onboarding-States: CLI too old), shown by `MainWindow`
/// over the empty window while `AppStore.isOnboarding`; it cannot be dismissed, and every toolbar action and
/// presenting menu item is disabled behind it (`AppStore.isPresenting`).
///
/// - Try Again re-runs detection (`AppStore.boot()`); the sheet keeps its state while `cli` is `.locating` and
///   closes when the CLI is ready.
/// - Locate… opens the system open panel for the executable; `AppStore.locate(executable:)` runs its `--version`
///   through the same gate and writes Settings' tool path only when it passes; a refused file is named in a
///   strip above the steps.
/// - Learn more opens the README in the browser; "Other ways to install" its Install section; Copy puts the
///   Homebrew command on the pasteboard.
///
/// Declared deviations from the boards: the command is `type.mono` (12 pt) where they draw 13 pt (no such token);
/// Needed reads `Capabilities.minimum` (0.9.1), where the board writes 0.9.0; the upgrade command names the tap
/// (`OnboardingCopy.upgradeCommand`).
struct CLIOnboardingSheet: View {
    @Environment(AppStore.self) private var app

    /// The board the sheet draws; kept while Try Again re-detects.
    @State private var state: OnboardingState
    /// Why the last Locate… was refused; cleared by the next attempt.
    @State private var locateError: CLIError?
    /// Previews only: draw the sheet as if a detection were running.
    @State private var isValidating = false

    /// - Parameters:
    ///   - state: The board to draw first (`OnboardingState.resolve`).
    ///   - locateError: Previews only: a refused Locate….
    ///   - validating: Previews only: a detection in flight.
    init(state: OnboardingState, locateError: CLIError? = nil, validating: Bool = false) {
        _state = State(initialValue: state)
        _locateError = State(initialValue: locateError)
        _isValidating = State(initialValue: validating)
    }

    // MARK: - Board values

    /// The sheet's width: 560 on the Onboarding board, 480 for the too-old card of Onboarding-States.
    static func width(for state: OnboardingState) -> CGFloat {
        if case .tooOld = state { 480 } else { 560 }
    }
    /// The horizontal padding: 28 on the Onboarding board, 24 on the too-old card (`Spacing.xxl`).
    static func padding(for state: OnboardingState) -> CGFloat {
        if case .tooOld = state { Spacing.xxl } else { headerTop }
    }
    /// The header's top padding (`padding: 28px …`); off the scale.
    static let headerTop: CGFloat = 28
    /// The app glyph's tile (`width: 44px; height: 44px; border-radius: 11px`).
    static let tileSize: CGFloat = 44
    static let tileRadius: CGFloat = 11
    /// The glyph inside the tile (`svg width="24"`).
    static let glyphSize: CGFloat = 24
    /// The white glyph on the accent tile (`stroke="#fff"`).
    static let glyphColor = Color.white
    /// The step number's circle (`.num { width: 22px; height: 22px }`).
    static let stepNumberSize: CGFloat = 22
    /// The gap between steps (`gap: 14px`); off the scale.
    static let stepGap: CGFloat = 14
    /// The command box's corners (`border-radius: 7px`); no 7 pt radius token exists.
    static let commandRadius: CGFloat = 7
    /// The command box's padding (`padding: 8px 10px`).
    static let commandPaddingH: CGFloat = 10
    /// The Found / Needed label column (`grid-template-columns: 90px …`).
    static let versionLabelWidth: CGFloat = 90
    /// The steps block's bottom padding (`padding: 12px 28px 20px`; 18 on the too-old card).
    static let stepsBottom: CGFloat = Spacing.xl
    static let tooOldStepsBottom: CGFloat = 18

    /// Try Again or Locate… is re-detecting (`AppStore.isRedetecting`, set before the first `await`).
    private var isDetecting: Bool {
        isValidating || app.isRedetecting || app.cli == .locating
    }

    private var padding: CGFloat { Self.padding(for: state) }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            steps
            footer
        }
        .frame(width: Self.width(for: state))
        .background(Color.surfaceWindow)
        .interactiveDismissDisabled()
        .onChange(of: app.cli) {
            if let next = OnboardingState.resolve(app.cli, binary: app.binary) {
                state = next
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous)
                .fill(Color.accent)
                .frame(width: Self.tileSize, height: Self.tileSize)
                .overlay {
                    Image(systemName: "shippingbox")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.glyphSize, height: Self.glyphSize)
                        .foregroundStyle(Self.glyphColor)
                }
                .accessibilityHidden(true)
            Text(state.title)
                .font(Font.Token.sheetTitle)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: Font.Token.Scale.sheetTitle.lineHeight)
                .padding(.top, Spacing.inline)
                .accessibilityAddTraits(.isHeader)
            intro
                .font(Font.Token.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, state == .missing ? Self.headerTop : Spacing.xxl)
        .padding(.horizontal, padding)
        .padding(.bottom, Spacing.s)
    }

    private var intro: Text {
        switch state {
        case .missing:
            let parts = OnboardingCopy.missingBody.components(separatedBy: OnboardingCopy.toolName)
            return parts.enumerated()
                .reduce(Text("")) { text, part in
                    part.offset == 0
                        ? text + Text(part.element)
                        : text + Text(OnboardingCopy.toolName).font(Font.Token.mono) + Text(part.element)
                }
        case .tooOld:
            return Text(OnboardingCopy.tooOldBody)
        }
    }

    @ViewBuilder private var steps: some View {
        VStack(alignment: .leading, spacing: state == .missing ? Self.stepGap : Spacing.m) {
            if let locateError {
                MessageStrip(.error, text: OnboardingCopy.locateFailure(locateError), density: .sheet)
            }
            switch state {
            case .missing:
                step(1, OnboardingCopy.installStep, spacing: Spacing.inline) {
                    command(OnboardingCopy.installCommand)
                    otherWays
                }
                step(2, OnboardingCopy.comeBackStep, spacing: Spacing.xs) {
                    usualPlaces
                }
            case .tooOld(let found, let needs, let path):
                versions(found: found, needs: needs, path: path)
                step(1, OnboardingCopy.upgradeStep, spacing: Spacing.inline) {
                    command(OnboardingCopy.upgradeCommand)
                }
                step(2, OnboardingCopy.thenTryAgain, spacing: 0) {
                    Text(OnboardingCopy.differentCopy)
                        .font(Font.Token.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(.top, state == .missing ? Spacing.m : Spacing.s)
        .padding(.horizontal, padding)
        .padding(.bottom, state == .missing ? Self.stepsBottom : Self.tooOldStepsBottom)
    }

    /// One numbered step: the accent-soft number, the semibold title, then `content`.
    private func step<Content: View>(
        _ number: Int, _ title: String, spacing: CGFloat, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Text("\(number)")
                .font(Font.Token.calloutSemibold)
                .foregroundStyle(Color.accent)
                .frame(width: Self.stepNumberSize, height: Self.stepNumberSize)
                .background(Color.accentSoft, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: spacing) {
                Text(title)
                    .font(Font.Token.bodyEmphasis)
                    .foregroundStyle(Color.textPrimary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The command box: the Homebrew line in mono and a small Copy button.
    private func command(_ text: String) -> some View {
        HStack(spacing: Spacing.s) {
            Text(text)
                .font(Font.Token.mono)
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(OnboardingCopy.copy) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .controlSize(.small)
        }
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Self.commandPaddingH)
        .background(Color.surfaceGrouped, in: RoundedRectangle(cornerRadius: Self.commandRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.commandRadius)
                .strokeBorder(Color.separator, lineWidth: Size.hairline))
    }

    /// `No Homebrew? Other ways to install are in the README.`
    private var otherWays: some View {
        HStack(spacing: Spacing.xs) {
            Text(OnboardingCopy.noHomebrew)
                .foregroundStyle(Color.textSecondary)
            link(OnboardingCopy.otherWays, font: Font.Token.captionMedium) { open(OnboardingCopy.installSection) }
            Text(OnboardingCopy.inTheReadme)
                .foregroundStyle(Color.textSecondary)
        }
        .font(Font.Token.caption)
    }

    /// `Skillcask looks in the usual places (…). Installed somewhere else? Point to it with Locate….`
    private var usualPlaces: some View {
        let places = OnboardingCopy.usualPlaces.enumerated()
            .reduce(Text(OnboardingCopy.comeBackLead)) { text, place in
                (place.offset == 0 ? text : text + Text(", "))
                    + Text(place.element).font(Font.Token.monoSmall)
            }
        return (places + Text(OnboardingCopy.comeBackTail))
            .font(Font.Token.callout)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The Found / Needed grid of the too-old card.
    private func versions(found: Version, needs: Version, path: String?) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.inline) {
            GridRow {
                Text(OnboardingCopy.found)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: Self.versionLabelWidth, alignment: .leading)
                Text(OnboardingCopy.foundValue(found, at: path))
                    .font(Font.Token.mono)
                    .foregroundStyle(Color.statusErrorText)
                    .textSelection(.enabled)
            }
            GridRow {
                Text(OnboardingCopy.needed)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: Self.versionLabelWidth, alignment: .leading)
                Text(OnboardingCopy.neededValue(needs))
                    .font(Font.Token.mono)
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .font(Font.Token.callout)
        .padding(.vertical, Spacing.cardGap)
        .padding(.horizontal, Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceGrouped, in: RoundedRectangle(cornerRadius: Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Color.separator, lineWidth: Size.hairline))
    }

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            link(OnboardingCopy.learnMore, font: Font.Token.calloutMedium) { open(OnboardingCopy.readme) }
            Spacer(minLength: Spacing.s)
            if isDetecting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(OnboardingCopy.detecting)
            }
            Button(OnboardingCopy.locate, action: locate)
                .disabled(isDetecting)
            Button(OnboardingCopy.tryAgain, action: tryAgain)
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(isDetecting)
        }
        .font(Font.Token.bodyMedium)
        .padding(.top, Spacing.m)
        .padding(.horizontal, padding)
        .padding(.bottom, Spacing.l)
        .background(Color.surfaceGrouped)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.separator)
                .frame(height: Size.hairline)
        }
    }

    /// An accent text link (the boards' `<a>`, `font-weight: 500`).
    private func link(_ title: String, font: Font, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .foregroundStyle(Color.accent)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }

    // MARK: - Actions

    private func tryAgain() {
        guard !isDetecting else { return }
        locateError = nil
        Task { await app.tryAgain() }
    }

    private func locate() {
        guard !isDetecting, let url = Self.chooseExecutable() else { return }
        locateError = nil
        Task {
            let error = await app.locate(executable: url)
            if error != .cancelled {
                locateError = error
            }
        }
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// The system open panel for one file: the executable to use, hidden folders shown so `~/.cargo/bin` can be
    /// reached.
    private static func chooseExecutable() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        // Keep the link the user picked (`/opt/homebrew/bin/skillcask`), not its Cellar target.
        panel.resolvesAliases = false
        panel.prompt = OnboardingCopy.locate.replacingOccurrences(of: "…", with: "")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
