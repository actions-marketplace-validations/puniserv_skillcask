import Foundation
import SkillcaskCore

/// `UpdateState` in `UserDefaults` under `appUpdates.*`; the suite is injected so tests never touch the real
/// defaults. Versions are stored as text and read back strictly, so a value edited by hand that is not a plain
/// version reads as unset.
public struct UpdateDefaults {
    /// The keys, in one place so tests, `smoke-app.sh`'s argument domain and a future migration can name them.
    public enum Key {
        /// `granted` / `declined`; absent is undecided.
        public static let consent = "appUpdates.consent"
        public static let lastCheckAt = "appUpdates.lastCheckAt"
        public static let latestSeen = "appUpdates.latestSeen"
        public static let skippedVersion = "appUpdates.skippedVersion"
        public static let hiddenUntil = "appUpdates.hiddenUntil"
        public static let hiddenForVersion = "appUpdates.hiddenForVersion"
        public static let remindAfter = "appUpdates.remindAfter"
        public static let awaitingRelaunch = "appUpdates.awaitingRelaunch"

        public static let all = [
            consent, lastCheckAt, latestSeen, skippedVersion, hiddenUntil, hiddenForVersion, remindAfter,
            awaitingRelaunch,
        ]
    }

    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> UpdateState {
        UpdateState(
            consent: defaults.string(forKey: Key.consent).flatMap(UpdateConsent.init(rawValue:)) ?? .undecided,
            lastCheckAt: defaults.object(forKey: Key.lastCheckAt) as? Date,
            latestSeen: version(Key.latestSeen),
            skippedVersion: version(Key.skippedVersion),
            hiddenUntil: defaults.object(forKey: Key.hiddenUntil) as? Date,
            hiddenForVersion: version(Key.hiddenForVersion),
            remindAfter: defaults.object(forKey: Key.remindAfter) as? Date,
            awaitingRelaunch: defaults.bool(forKey: Key.awaitingRelaunch))
    }

    /// Writes every key; a nil value (and `undecided`, `false`) removes it.
    public func save(_ state: UpdateState) {
        set(state.consent == .undecided ? nil : state.consent.rawValue, Key.consent)
        set(state.lastCheckAt, Key.lastCheckAt)
        set(state.latestSeen?.description, Key.latestSeen)
        set(state.skippedVersion?.description, Key.skippedVersion)
        set(state.hiddenUntil, Key.hiddenUntil)
        set(state.hiddenForVersion?.description, Key.hiddenForVersion)
        set(state.remindAfter, Key.remindAfter)
        set(state.awaitingRelaunch ? true : nil, Key.awaitingRelaunch)
    }

    /// The launch hook: loads, clears `awaitingRelaunch` (`UpdateState.launched`), saves, and returns the state.
    @discardableResult
    public func launched() -> UpdateState {
        var state = load()
        state.launched()
        save(state)
        return state
    }

    private func version(_ key: String) -> Version? {
        defaults.string(forKey: key).flatMap(Version.init(strict:))
    }

    private func set(_ value: Any?, _ key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
