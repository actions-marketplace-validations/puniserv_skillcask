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
        #expect(settings.environmentVariables.isEmpty && settings.environmentOverrides.isEmpty)
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
            settings.environmentVariables = [
                SettingsStore.EnvironmentVariable(name: "HTTPS_PROXY", value: "http://proxy:3128"),
                SettingsStore.EnvironmentVariable(name: "GITHUB_TOKEN", value: "x"),
            ]
            settings.commitEnvironmentValues()
        }
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.binaryPath == "/opt/homebrew/bin/skillcask")
        #expect(reloaded.openAtLaunch == .personal)
        #expect(reloaded.recentProjects == [site, api])
        #expect(reloaded.lastScope == .project(api))
        #expect(reloaded.checkUpdatesOnOpen)
        #expect(reloaded.environmentVariables.map(\.name) == ["HTTPS_PROXY", "GITHUB_TOKEN"])
        // A refused name keeps its row but never its value on disk.
        #expect(reloaded.environmentVariables.map(\.value) == ["http://proxy:3128", ""])
        reloaded.lastScope = .personal
        reloaded.forget(project: site)
        let again = SettingsStore(defaults: defaults)
        #expect(again.lastScope == .personal && again.recentProjects == [api])
        again.lastScope = nil
        #expect(SettingsStore(defaults: defaults).lastScope == nil)
    }

    /// Only the names the policy allows become overrides: no token variable, nothing the policy sets itself, no
    /// malformed or empty name; a name typed twice keeps the later value.
    @Test func overridesKeepOnlyWhatThePolicyAllows() {
        let (defaults, name) = Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.environmentVariables = [
            "HTTPS_PROXY=a", "GITHUB_TOKEN=t", "GH_TOKEN=t", "COMPOSER_AUTH=t", "PATH=/evil", "HOME=/evil",
            "NO_COLOR=0", "SKILLCASK_AGENT=1", "lower=x", "=x", "SKILLCASK_CACHE_DIR=/c", "HTTPS_PROXY=b",
        ]
        .map {
            let parts = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            return SettingsStore.EnvironmentVariable(name: parts[0], value: parts[1])
        }
        #expect(settings.environmentOverrides == ["HTTPS_PROXY": "b", "SKILLCASK_CACHE_DIR": "/c"])
    }
}
