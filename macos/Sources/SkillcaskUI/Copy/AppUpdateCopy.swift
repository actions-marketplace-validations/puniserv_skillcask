import SkillcaskCore

/// The words of the app-update check (D51): the sidebar card (U1), the app menu item and the manual check's alerts
/// (U4). The brief's copy wins where the handoff differs: no release date (the cask has none), no command-line tool
/// card, the consent prompt of decision 3.
public enum AppUpdateCopy {
    // MARK: - Card (U1)

    /// What VoiceOver reads for the card and announces once when it appears.
    public static let cardLabel = "Skillcask update available"
    public static let consentLabel = "Daily update check"
    public static let awaitingLabel = "Waiting for the Skillcask update"

    public static func availableTitle(_ version: Version) -> String {
        "Skillcask \(version) is available"
    }

    public static func availableSubtitle(installed: Version) -> String {
        "You have \(installed)"
    }

    /// The icon-only × on the card.
    public static let hide = "Hide until the next version"
    public static let seeWhatsNew = "See What’s New…"

    public static let consentTitle = "Check for new versions daily?"
    /// Decision 3: what the daily check asks, of whom, and what it never sends.
    public static let consentBody =
        "Skillcask asks GitHub (raw.githubusercontent.com) once a day, with no account, project or skill information."
    public static let checkDaily = "Check Daily"
    public static let notNow = "Not Now"

    public static let awaitingTitle = "Waiting for the update"
    public static let awaitingBody = "Command copied. After Homebrew finishes, quit and reopen Skillcask."

    // MARK: - Sheet (U2/U3; phase 4b completes it)

    public static let releaseNotes = "Release Notes on GitHub"
    public static let close = "Close"

    // MARK: - App menu (U4)

    public static let checkForUpdates = "Check for Updates…"

    public static func updateTo(_ version: Version) -> String {
        "Update to \(version)…"
    }

    // MARK: - Manual check alerts (U4)

    public static let upToDateTitle = "You’re up to date"

    public static func upToDateMessage(_ version: Version) -> String {
        "Skillcask \(version) is the newest version."
    }

    public static let failedTitle = "Couldn’t check for updates"
    /// `latest: null`: the CLI reached the tap but its cask named no version it could read.
    public static let unknownMessage = "GitHub answered, but named no version Skillcask could read. Try again later."

    /// The CLI set in Settings › General predates `self-check` (`Capabilities.Feature.selfCheck`; the release is
    /// `Capabilities.shipped`).
    public static func unsupportedMessage(_ version: Version) -> String {
        "The command-line tool Skillcask uses (\(version)) is too old to check for updates. In Settings › General, "
            + "use the detected one or choose a newer one."
    }

    public static let tryAgain = "Try Again"
    public static let ok = "OK"

    /// The alert line of a failed check: the CLI's error sentence, then what to do when it says.
    public static func failedMessage(_ error: CLIError) -> String {
        let message = ErrorCopy.message(for: error)
        return [message.title, message.action].compactMap { $0 }.joined(separator: " ")
    }
}
