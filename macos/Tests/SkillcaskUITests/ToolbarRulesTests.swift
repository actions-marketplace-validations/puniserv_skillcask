import SkillcaskDomain
import Testing

@testable import SkillcaskUI

/// The designer's enablement rules for Sync and Update All, over the design fixtures and the Overview grid.
@Suite struct ToolbarRulesTests {
    @Test func syncIsEnabledOnlyWhenTheLockAndFilesDisagree() {
        // api: jira-syntax and sql-review not installed, deploy-checklist changed on disk.
        #expect(ToolbarRules.canSync(DesignFixtures.api))
        #expect(ToolbarRules.canSync(DesignFixtures.apiOffline))
        // website: three installed rows, all matching the lock.
        #expect(!ToolbarRules.canSync(DesignFixtures.website))
        #expect(!ToolbarRules.canSync(DesignFixtures.personal))
        #expect(!ToolbarRules.canSync(DesignFixtures.emptyAfterSetUp))
        #expect(!ToolbarRules.canSync(nil))
    }

    @Test func updateAllCountsPackagesWithAnUpdateInsideTheirRange() {
        #expect(ToolbarRules.updateAllCount(DesignFixtures.api) == 2)
        #expect(ToolbarRules.canUpdateAll(DesignFixtures.api))
        #expect(ToolbarRules.updateAllCount(DesignFixtures.website) == 0)
        #expect(!ToolbarRules.canUpdateAll(DesignFixtures.website))
        // Offline, `outdated` has not answered: nothing to update, the button is disabled.
        #expect(ToolbarRules.updateAllCount(DesignFixtures.apiOffline) == 0)
        #expect(!ToolbarRules.canUpdateAll(nil))
    }

    @Test func overviewGridIsTwoColumnsAtTheBoardAndOneAtTheMinimumWindow() {
        // The Overview board: 1280 − 220 − 360 = 700 pt detail column.
        #expect(ScopeOverviewView.columnCount(for: 700) == 2)
        // The 960 pt minimum window with the sidebar and list at their ideal widths.
        #expect(ScopeOverviewView.columnCount(for: 380) == 1)
        #expect(ScopeOverviewView.columnCount(for: ScopeOverviewView.twoColumnMinWidth) == 2)
        #expect(ScopeOverviewView.columnCount(for: ScopeOverviewView.twoColumnMinWidth - 1) == 1)
    }
}
