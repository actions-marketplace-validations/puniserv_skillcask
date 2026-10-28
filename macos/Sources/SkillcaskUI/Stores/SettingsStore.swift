import Foundation
import Observation
import SkillcaskCore

/// The user's settings (S14), backed by `UserDefaults` and read by the other stores. Every property writes
/// through on change, so a value survives a relaunch; the suite is injected so tests never touch the real
/// defaults. Nothing here runs the CLI: the binary path is only stored, `AppStore` validates it.
@MainActor @Observable public final class SettingsStore {
    /// Which scope the window opens with (Settings › General, "Open at launch").
    public enum OpenAtLaunch: String, CaseIterable, Hashable, Sendable {
        case lastScope
        case personal
    }

    /// The keys, in one place so the tests and a future migration can name them.
    enum Key {
        static let binaryPath = "binaryPath"
        static let openAtLaunch = "openAtLaunch"
        static let recentProjects = "recentProjects"
        static let lastScope = "lastScope"
        static let checkUpdatesOnOpen = "checkUpdatesOnOpen"
        static let searchSkillsSh = "searchSkillsSh"
        /// The value stored under `lastScope` for the personal scope; a project stores its path.
        static let personalScope = "personal"
    }

    private let defaults: UserDefaults

    // MARK: - State

    /// A path the user chose over the bundled or `PATH` binary; nil means auto-detect.
    public var binaryPath: String? {
        didSet { defaults.set(binaryPath, forKey: Key.binaryPath) }
    }

    /// Which scope the window opens with.
    public var openAtLaunch: OpenAtLaunch {
        didSet { defaults.set(openAtLaunch.rawValue, forKey: Key.openAtLaunch) }
    }

    /// Project roots, most recent first, as the sidebar lists them under Projects.
    public var recentProjects: [URL] {
        didSet { defaults.set(recentProjects.map(\.path), forKey: Key.recentProjects) }
    }

    /// The scope open when the app last quit; what `.lastScope` reopens.
    public var lastScope: Scope? {
        didSet { defaults.set(Self.stored(lastScope), forKey: Key.lastScope) }
    }

    /// Run `outdated` when a scope opens (off by default: it hits GitHub unauthenticated, ADR §9).
    public var checkUpdatesOnOpen: Bool {
        didSet { defaults.set(checkUpdatesOnOpen, forKey: Key.checkUpdatesOnOpen) }
    }

    /// Whether search includes skills.sh; nil until the consent card was answered (S8).
    public var searchSkillsSh: Bool? {
        didSet { defaults.set(searchSkillsSh, forKey: Key.searchSkillsSh) }
    }

    /// - Parameter defaults: The suite to read and write; tests pass their own.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        binaryPath = defaults.string(forKey: Key.binaryPath)
        openAtLaunch =
            defaults.string(forKey: Key.openAtLaunch).flatMap(OpenAtLaunch.init(rawValue:)) ?? .lastScope
        recentProjects = (defaults.stringArray(forKey: Key.recentProjects) ?? []).map { URL(fileURLWithPath: $0) }
        lastScope = defaults.string(forKey: Key.lastScope).flatMap(Self.scope(stored:))
        checkUpdatesOnOpen = defaults.bool(forKey: Key.checkUpdatesOnOpen)
        searchSkillsSh = defaults.object(forKey: Key.searchSkillsSh) as? Bool
    }

    // MARK: - Actions

    /// Puts `root` first in the recents, once.
    public func remember(project root: URL) {
        let standardized = root.standardizedFileURL
        recentProjects = [standardized] + recentProjects.filter { $0 != standardized }
    }

    /// Drops `root` from the recents ("Remove from Sidebar").
    public func forget(project root: URL) {
        let standardized = root.standardizedFileURL
        recentProjects.removeAll { $0 == standardized }
    }

    // MARK: - Storage

    static func stored(_ scope: Scope?) -> String? {
        switch scope {
        case nil: nil
        case .personal: Key.personalScope
        case .project(let url): url.path
        }
    }

    static func scope(stored text: String) -> Scope? {
        text == Key.personalScope ? .personal : .project(at: text)
    }
}
