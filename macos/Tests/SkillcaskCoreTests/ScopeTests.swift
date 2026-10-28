import Foundation
import Testing

@testable import SkillcaskCore

/// Mirrors `config_dir_precedence` in `src/scope.rs`.
@Suite struct ScopeManifestTests {
    let home = URL(fileURLWithPath: "/h", isDirectory: true)

    @Test(arguments: [
        ([:], "/h/.config/skillcask"),
        (["XDG_CONFIG_HOME": "/x"], "/x/skillcask"),
        (["XDG_CONFIG_HOME": "/x", "SKILLCASK_HOME": "/s"], "/s"),
        (["SKILLCASK_HOME": ""], "/h/.config/skillcask"),
        (["XDG_CONFIG_HOME": ""], "/h/.config/skillcask"),
        (["HOME": "/e"], "/e/.config/skillcask"),
        (["HOME": ""], "/h/.config/skillcask"),
    ])
    func configDirectoryPrecedence(environment: [String: String], expected: String) {
        #expect(Scope.configDirectory(environment: environment, home: home).path == expected)
    }

    @Test func personalManifestIsInTheConfigDirectory() {
        let manifest = Scope.personal.manifest(environment: ["SKILLCASK_HOME": "/s"])
        #expect(manifest.path == "/s/skills.toml")
    }

    @Test func projectManifestIsInTheRootWhateverTheEnvironment() {
        let manifest = Scope.project(at: "/p/app").manifest(environment: ["SKILLCASK_HOME": "/s"])
        #expect(manifest.path == "/p/app/skills.toml")
    }
}
