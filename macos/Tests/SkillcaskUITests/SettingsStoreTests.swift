import Foundation
import SkillcaskCore
import Testing

@testable import SkillcaskUI

/// Defaults and persistence of `SettingsStore` over an injected `UserDefaults` suite.
@Suite @MainActor struct SettingsStoreTests {
    static func suite() -> (UserDefaults, String) {
        let name = "SettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test func defaultsAreAutoDetectLastScopeNoRecentsNoChecks() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.binaryPath == nil)
        #expect(settings.openAtLaunch == .lastScope)
        #expect(settings.recentProjects.isEmpty)
        #expect(settings.lastScope == nil)
        #expect(!settings.checkUpdatesOnOpen)
        #expect(settings.searchSkillsSh == nil)
    }

    @Test func everyValueRoundTripsThroughTheSuite() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let api = URL(fileURLWithPath: "/Users/someone/work/api")
        let site = URL(fileURLWithPath: "/Users/someone/work/site")
        do {
            let settings = SettingsStore(defaults: defaults)
            settings.binaryPath = "/opt/homebrew/bin/skillcask"
            settings.openAtLaunch = .personal
            settings.remember(project: site)
            settings.remember(project: api)
            settings.remember(project: site)
            settings.lastScope = .project(api)
            settings.checkUpdatesOnOpen = true
            settings.searchSkillsSh = false
        }
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.binaryPath == "/opt/homebrew/bin/skillcask")
        #expect(reloaded.openAtLaunch == .personal)
        #expect(reloaded.recentProjects == [site, api])
        #expect(reloaded.lastScope == .project(api))
        #expect(reloaded.checkUpdatesOnOpen)
        #expect(reloaded.searchSkillsSh == false)
        reloaded.lastScope = .personal
        reloaded.forget(project: site)
        let again = SettingsStore(defaults: defaults)
        #expect(again.lastScope == .personal && again.recentProjects == [api])
        again.lastScope = nil
        #expect(SettingsStore(defaults: defaults).lastScope == nil)
    }
}
