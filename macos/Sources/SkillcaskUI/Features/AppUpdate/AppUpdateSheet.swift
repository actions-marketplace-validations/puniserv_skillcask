import SkillcaskCore
import SkillcaskUpdates
import SwiftUI

/// The update sheet (U2/U3), presented by `MainWindow` for `AppUpdateStore.sheet` on a host of its own, never over
/// the onboarding sheet or a scope sheet. A minimal body for now (title, versions, the release page, Close); phase
/// 4b replaces it with the install-method steps and footers. Esc closes it with no state change.
struct AppUpdateSheet: View {
    let version: Version
    let installed: Version
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(AppUpdateCopy.availableTitle(version))
                .font(Font.Token.sheetTitle)
                .foregroundStyle(Color.textPrimary)
            Text(AppUpdateCopy.availableSubtitle(installed: installed) + ".")
                .font(Font.Token.body)
                .foregroundStyle(Color.textSecondary)
            HStack {
                if let page = UpdateLinks.releasePage(for: version) {
                    Button(AppUpdateCopy.releaseNotes) { openURL(page) }
                }
                Spacer()
                Button(AppUpdateCopy.close, action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 480, alignment: .leading)
        .background(Color.surfaceWindow)
    }
}
