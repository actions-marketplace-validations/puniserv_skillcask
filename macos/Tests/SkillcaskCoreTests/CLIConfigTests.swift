import Foundation
import Testing

@testable import SkillcaskCore

/// `CLIConfig`: config.toml's path.
@Suite struct CLIConfigTests {
    @Test func fileFollowsTheConfigDirectory() {
        let home = URL(fileURLWithPath: "/Users/me")
        #expect(CLIConfig.file(environment: [:], home: home).path == "/Users/me/.config/skillcask/config.toml")
        #expect(CLIConfig.file(environment: ["SKILLCASK_HOME": "/s"], home: home).path == "/s/config.toml")
    }
}
