import Foundation
import Testing

@testable import SkillcaskCore

/// `CLIConfig`: config.toml's path and its `[search] skills-sh`, read as data.
@Suite struct CLIConfigTests {
    @Test(
        arguments: [
            ("", nil),
            ("[policy]\nmin-release-age = \"72h\"\n", nil),
            ("[search]\nskills-sh = true\n", true),
            ("[search]\nskills-sh = false # asked once\n", false),
            ("[ search ]\n\"skills-sh\" = true\n", true),
            ("search.skills-sh = false\n", false),
            ("[policy]\nskills-sh = true\n", nil),
            ("[search]\nskills-sh = \"yes\"\n", nil),
            ("# [search]\n# skills-sh = true\n", nil),
            ("[search]\nskills-sh = true\n[agents]\ntargets = [\"claude\"]\n", true),
            ("search = { skills-sh = true }\n", nil),
            ("[\"search\"]\nskills-sh = true\n", true),
            ("[policy]\nnote = \"\"\"\n[search]\nskills-sh = true\n\"\"\"\n", nil),
            ("[policy]\nnote = '''\n[search]\nskills-sh = true\n'''\n[search]\nskills-sh = false\n", false),
            ("[policy]\nnote = \"\"\"one line\"\"\"\n[search]\nskills-sh = true\n", true),
        ] as [(String, Bool?)])
    func readsSkillsSh(text: String, expected: Bool?) {
        #expect(CLIConfig.skillsSh(in: text) == expected)
    }

    @Test func fileFollowsTheConfigDirectory() {
        let home = URL(fileURLWithPath: "/Users/me")
        #expect(CLIConfig.file(environment: [:], home: home).path == "/Users/me/.config/skillcask/config.toml")
        #expect(CLIConfig.file(environment: ["SKILLCASK_HOME": "/s"], home: home).path == "/s/config.toml")
    }
}
