import Foundation
import SkillcaskCore
import SkillcaskDomain
import Testing

@testable import SkillcaskUI

/// The toast says the whole sentence with the skill names semibold, Sync counts the CLI's
/// `installed` lines, and Add Skill… waits for the run in flight.
@Suite @MainActor struct OutcomeLineTests {
    let client = FakeCLIClient()
    let scope = Scope.project(URL(fileURLWithPath: "/tmp/outcome-line-tests"))

    /// AddSkill board: "Added **jira-syntax** and **jira-communication** (v4.2.0)".
    @Test func everySkillNameIsSemibold() {
        let text = OutcomeCopy.added(["jira-syntax", "jira-communication"], version: "4.2.0")
        #expect(
            Toast.emphasized(text, emphasis: ["jira-syntax", "jira-communication"])
                == ["jira-syntax", "jira-communication"])
        #expect(Toast.emphasized("Added a and ab (1.0)", emphasis: ["a", "ab"]) == ["a", "ab"], "in order")
        #expect(Toast.emphasized("Updated pdf to 1.4.0", emphasis: ["pdf"]) == ["pdf"])
        #expect(Toast.emphasized("Synced api", emphasis: []) == [] && Toast.emphasized("x", emphasis: ["y"]) == [])
        #expect(Toast.lineLimit == 2)
        #expect(ToastMessage(text: "Updated pdf to 1.4.0", emphasis: "pdf").emphasis == ["pdf"])
    }

    /// Flow-F5: "Synced api · 1 skill installed", from `installed <skill> (<package> <version>)` (src/commands.rs 644).
    @Test(.timeLimit(.minutes(1))) func syncCountsTheInstalledLines() async {
        await client.lines(
            .install(frozen: false), in: scope,
            ["installed jira-syntax (netresearch/agent-jira-skill 4.2.0)", "installed pdf (anthropics/skills 1.2.0)"])
        let store = ScopeStore(scope: scope, client: client, capabilities: Capabilities(version: Capabilities.minimum))
        { _ in SkillText.parse("") }
        let runner = ActionRunner(queue: MutationQueue())
        await runner.sync(in: store)
        #expect(runner.toast?.text == "Synced outcome-line-tests · 2 skills installed")
        #expect(ActionCopy.synced("api", installed: 1) == "Synced api · 1 skill installed")
        #expect(ActionCopy.synced("api", installed: 0) == "Synced api")
    }

    /// Flow-F2: Add Skill… is "Disabled while another command runs in this scope."
    @Test func addSkillWaitsForTheRunInFlight() {
        #expect(ToolbarRules.canAddSkill(DesignFixtures.api, isBusy: false))
        #expect(!ToolbarRules.canAddSkill(DesignFixtures.api, isBusy: true))
        #expect(!ToolbarRules.canAddSkill(nil, isBusy: false))
        let runner = ActionRunner(queue: MutationQueue())
        runner.preloadRunning(title: ActionCopy.syncing, in: .personal)
        #expect(!ToolbarRules.canAddSkill(DesignFixtures.api, isBusy: runner.isRunning), "one run in the whole app")
        let action = EmptyState.Action.primary(EmptyCopy.addSkill) {}
        #expect(!action.isDisabled && action.disabled(true).isDisabled)
    }
}
