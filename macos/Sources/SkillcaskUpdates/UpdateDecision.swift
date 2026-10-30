import Foundation
import SkillcaskCore

/// What the sidebar card slot shows for the update check. One slot, so one state.
public enum UpdateCard: Hashable, Sendable {
    case none
    /// "Check for new versions daily?": consent was never answered. The UI shows it only once the CLI is ready and
    /// onboarding is not up.
    case consentPrompt
    /// `Skillcask X is available`.
    case available(Version)
    /// `Waiting for the update`: the Homebrew command was copied this launch.
    case awaitingRelaunch
}

/// What "Check for Updates…" reports. Ignores skip, × and Remind: the user asked.
public enum ManualCheckResult: Hashable, Sendable {
    case available(Version)
    /// `You’re up to date` / `Skillcask X is the newest version.` with the installed version.
    case upToDate(Version)
    /// The CLI answered but the cask held no version it could read (`latest: null`).
    case unknown
}

/// The pure rules of the update check (D51). The installed version is the app's own (`AppVersion`), which is the
/// bundled CLI's; nil (`swift run`, fixtures) turns everything off.
public enum UpdateDecision {
    /// The card, in this order: off without an installed version; `awaitingRelaunch` until the next launch; an
    /// available version unless skipped (that version only), hidden by × (that version and older, until
    /// `hiddenUntil`) or by Remind (any version, until `remindAfter`); else the consent prompt while undecided. A
    /// `hiddenUntil` or `remindAfter` further ahead than its interval (the clock went back) has expired.
    public static func card(installed: Version?, state: UpdateState, now: Date) -> UpdateCard {
        guard installed != nil else { return .none }
        if state.awaitingRelaunch {
            return .awaitingRelaunch
        }
        if let latest = knownUpdate(installed: installed, latest: state.latestSeen), !isHidden(latest, state, now) {
            return .available(latest)
        }
        return state.consent == .undecided ? .consentPrompt : .none
    }

    /// The version the app menu offers (`Update to X…`) and the sheet opens on: newer than installed, whatever the
    /// card hides.
    public static func knownUpdate(installed: Version?, latest: Version?) -> Version? {
        guard let installed, let latest, latest.isStrict, latest > installed else { return nil }
        return latest
    }

    /// A manual check's answer for `document`, compared with the app's version, not the CLI's `newer` (a CLI set in
    /// Settings may be another version than the app).
    public static func manual(installed: Version, document: SelfCheckDocument) -> ManualCheckResult {
        guard let latest = document.latestVersion else { return .unknown }
        return latest > installed ? .available(latest) : .upToDate(installed)
    }

    private static func isHidden(_ latest: Version, _ state: UpdateState, _ now: Date) -> Bool {
        if state.skippedVersion == latest {
            return true
        }
        if active(state.remindAfter, UpdateState.remindInterval, now) {
            return true
        }
        if let version = state.hiddenForVersion, latest <= version,
            active(state.hiddenUntil, UpdateState.hideInterval, now)
        {
            return true
        }
        return false
    }

    /// `now` is before `until`, and `until` is no further ahead than the interval that set it: a date further out
    /// was set while the clock ran ahead (or went back since), so it has expired, as `UpdateSchedule.isDue` treats
    /// a future `lastCheckAt`.
    private static func active(_ until: Date?, _ interval: TimeInterval, _ now: Date) -> Bool {
        guard let until, now < until else { return false }
        return until.timeIntervalSince(now) <= interval
    }
}

/// When the automatic check runs: with consent, on launch when the last answer is 24 hours old, then every 24 hours.
/// A manual check never asks.
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Never checked, 24 hours since, or a `lastCheckAt` in the future (the clock went back): due.
    public static func isDue(lastCheckAt: Date?, now: Date) -> Bool {
        guard let last = lastCheckAt, last <= now else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// When the next automatic check is due: `now` when it already is.
    public static func nextCheck(lastCheckAt: Date?, now: Date) -> Date {
        guard let last = lastCheckAt, !isDue(lastCheckAt: last, now: now) else { return now }
        return last.addingTimeInterval(interval)
    }

    /// Whether an automatic check may run now: only with consent, and only when due. No consent, no request.
    public static func shouldCheckAutomatically(_ state: UpdateState, now: Date) -> Bool {
        state.consent == .granted && isDue(lastCheckAt: state.lastCheckAt, now: now)
    }
}
