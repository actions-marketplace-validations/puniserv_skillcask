import Foundation
import SkillcaskCore
import SkillcaskDomain
import Testing

@testable import SkillcaskUI

/// The Add Skill sheet's source filter: the chips with their per-source counts, the filtered and sorted results, the
/// selection a filter hides, the filter surviving a new query, and the header and empty-state copy. Client-side
/// only: every test filters one `search --json` document. The scope is the api board's snapshot, whose repositories
/// are packagist and acme (allowed) and github (blocked).
@Suite @MainActor struct AddSkillSourceFilterTests {
    typealias Chip = SearchStore.SourceChip

    let client = FakeCLIClient()
    let scope = Scope.project(URL(fileURLWithPath: "/tmp/add-source-filter-tests"))
    static let searchJira = Invocation.Command.search(query: "jira", skillsSh: nil, remember: false)
    static let searchPdf = Invocation.Command.search(query: "pdf", skillsSh: nil, remember: false)

    /// Every source kind the chips know: packagist, acme (also as `ACME`), skills.sh, a source matching no repository
    /// (`internal`) and a result without `source`.
    static let mixedJSON = """
        {"results":[\
        {"name":"netresearch/agent-jira-skill","description":null,"source":"packagist","installs":4100},\
        {"name":"acme/jira-triage","description":null,"source":"acme","installs":38},\
        {"name":"github:ankit/jira-helper","description":null,"source":"skills.sh","installs":900},\
        {"name":"atlassian/jira-cli-skill","description":null,"source":"packagist","installs":2200},\
        {"name":"acme/jira-board","description":null,"source":"ACME","installs":null},\
        {"name":"team/jira-internal","description":null,"source":"internal","installs":null},\
        {"name":"kolya/jira-to-md","description":null,"installs":610}\
        ],"skills-sh":true}
        """
    /// A later query's answer: packagist and skills.sh only.
    static let pdfJSON = """
        {"results":[\
        {"name":"anthropics/pdf","description":null,"source":"packagist","installs":120},\
        {"name":"github:anthropics/skills/pdf","description":null,"source":"skills.sh","installs":5000}\
        ],"skills-sh":true}
        """
    /// acme's results carry no install count.
    static let uncountedAcmeJSON = """
        {"results":[\
        {"name":"netresearch/agent-jira-skill","description":null,"source":"packagist","installs":4100},\
        {"name":"acme/jira-triage","description":null,"source":"acme","installs":null},\
        {"name":"acme/jira-board","description":null,"source":"acme","installs":null}\
        ],"skills-sh":true}
        """

    func search(debounce: Duration = .zero) -> SearchStore {
        let capabilities = Capabilities(version: Capabilities.minimum)
        let store = ScopeStore(scope: scope, client: client, capabilities: capabilities) { _ in SkillText.parse("") }
        store.preload(snapshot: DesignFixtures.api)
        return SearchStore(store: store, debounce: debounce)
    }

    /// A store showing `json` for "jira", with skills.sh as the document says.
    func loaded(_ json: String = Self.mixedJSON, selection: String? = nil) -> SearchStore {
        let search = search()
        let document = DesignFixtures.decode(SearchDocument.self, json: json)
        search.preload(
            query: "jira", results: .loaded(document), skillsSh: document.skillsSh, selection: selection)
        return search
    }

    /// A scope whose only repositories are `repositories`, in that order.
    static func snapshot(_ repositories: [(name: String, allowed: Bool)]) -> ScopeSnapshot {
        let rows = repositories.map {
            #"{"name":"\#($0.name)","type":"vcs","url":"https://example.com/","allowed":\#($0.allowed)}"#
        }
        let status = DesignFixtures.decode(
            StatusDocument.self,
            json: #"{"ok":true,"entries":[],"repositories":[\#(rows.joined(separator: ","))]}"#)
        return ScopeSnapshot(status: status, audit: nil, doctor: nil, outdated: nil)
    }

    /// A store on a scope with `repositories`, showing `json` for "jira".
    func loaded(_ json: String, repositories: [(name: String, allowed: Bool)]) -> SearchStore {
        let search = loaded(json)
        search.store.preload(snapshot: Self.snapshot(repositories))
        return search
    }

    // MARK: - Chips

    @Test func chipsAreTheAllowedRepositoriesThenSkillsShThenUnmatchedSourcesWithTheirCounts() {
        let search = loaded()
        #expect(
            search.sourceChips == [
                Chip(name: "packagist", kind: .packagist, count: 2),
                Chip(name: "acme", kind: .custom("acme"), count: 2),
                Chip(name: "skills.sh", kind: .skillsSh, count: 1),
                Chip(name: "internal", kind: .custom("internal"), count: 1),
            ])
    }

    @Test func aBlockedRepositoryIsNotAChip() {
        let search = loaded()
        #expect(search.repositories.contains { $0.name == "github" && !$0.allowed }, "api's policy blocks github")
        #expect(!search.sourceChips.contains { $0.name == "github" || $0.kind == .github })
    }

    @Test func aResultFromTheBlockedRepositoryIsNoChipAndCountsOnlyInTheTotal() {
        let json = """
            {"results":[\
            {"name":"netresearch/agent-jira-skill","description":null,"source":"packagist","installs":4100},\
            {"name":"github:ankit/jira-helper","description":null,"source":"github","installs":900}\
            ],"skills-sh":false}
            """
        let search = loaded(json)
        #expect(search.isBlocked(search.sortedResults[1]), "github is blocked")
        #expect(
            search.sourceChips == [
                Chip(name: "packagist", kind: .packagist, count: 1),
                Chip(name: "acme", kind: .custom("acme"), count: 0),
            ])
        #expect(search.totalResultCount == 2)
    }

    @Test func skillsShIsAChipOnlyWhenEnabled() {
        let json = """
            {"results":[{"name":"netresearch/agent-jira-skill","description":null,"source":"packagist",\
            "installs":null}],"skills-sh":false}
            """
        let search = loaded(json)
        #expect(
            search.sourceChips == [
                Chip(name: "packagist", kind: .packagist, count: 1),
                Chip(name: "acme", kind: .custom("acme"), count: 0),
            ])
    }

    @Test func aResultWithoutASourceCountsOnlyInTheTotal() {
        let search = loaded()
        #expect(search.totalResultCount == 7)
        #expect(search.sourceChips.map(\.count).reduce(0, +) == 6, "kolya/jira-to-md has no source")
    }

    @Test func aSourceMatchesItsChipByNameIgnoringCaseOnly() {
        let search = loaded()
        search.sourceFilter = "acme"
        #expect(search.filteredResults.map(\.name) == ["acme/jira-triage", "acme/jira-board"], "ACME is acme")
        let json = """
            {"results":[\
            {"name":"netresearch/agent-jira-skill","description":null,"source":"packagist","installs":null},\
            {"name":"atlassian/jira-cli-skill","description":null,"source":"composer","installs":null}\
            ],"skills-sh":false}
            """
        let aliased = loaded(json)
        #expect(
            aliased.sourceChips == [
                Chip(name: "packagist", kind: .packagist, count: 1),
                Chip(name: "acme", kind: .custom("acme"), count: 0),
                Chip(name: "composer", kind: .packagist, count: 1),
            ], "composer is no alias of packagist")
        aliased.sourceFilter = "packagist"
        #expect(aliased.filteredResults.map(\.name) == ["netresearch/agent-jira-skill"])
    }

    @Test func unmatchedSourcesOfOneKindAreChipsOfTheirOwn() {
        let json = """
            {"results":[\
            {"name":"team/a","description":null,"source":"foo.git","installs":null},\
            {"name":"team/b","description":null,"source":"bar.git","installs":null},\
            {"name":"team/c","description":null,"source":"foo.git","installs":null},\
            {"name":"atlassian/jira-cli-skill","description":null,"source":"composer","installs":null}\
            ],"skills-sh":false}
            """
        let search = loaded(json)
        #expect(
            search.sourceChips == [
                Chip(name: "packagist", kind: .packagist, count: 0),
                Chip(name: "acme", kind: .custom("acme"), count: 0),
                Chip(name: "foo.git", kind: .git, count: 2),
                Chip(name: "bar.git", kind: .git, count: 1),
                Chip(name: "composer", kind: .packagist, count: 1),
            ])
        search.sourceFilter = "bar.git"
        #expect(search.filteredResults.map(\.name) == ["team/b"])
    }

    @Test func aRepositoryNamedComposerCountsOnlyItsOwnResults() {
        let json = """
            {"results":[\
            {"name":"netresearch/agent-jira-skill","description":null,"source":"packagist","installs":null},\
            {"name":"atlassian/jira-cli-skill","description":null,"source":"composer","installs":null}\
            ],"skills-sh":false}
            """
        let search = loaded(json, repositories: [("packagist", true), ("composer", true)])
        #expect(
            search.sourceChips == [
                Chip(name: "packagist", kind: .packagist, count: 1),
                Chip(name: "composer", kind: .packagist, count: 1),
            ])
    }

    @Test func aRepositoryNamedSkillsShIsTheOneSkillsShChip() {
        let json = """
            {"results":[{"name":"github:ankit/jira-helper","description":null,"source":"skills.sh",\
            "installs":null}],"skills-sh":true}
            """
        let search = loaded(json, repositories: [("packagist", true), ("skills.sh", true)])
        #expect(
            search.sourceChips == [
                Chip(name: "packagist", kind: .packagist, count: 0),
                Chip(name: "skills.sh", kind: .skillsSh, count: 1),
            ])
    }

    @Test func aFilteredRepositoryThatBecomesBlockedShowsAndCountsNothing() {
        let json = """
            {"results":[\
            {"name":"netresearch/agent-jira-skill","description":null,"source":"packagist","installs":4100},\
            {"name":"github:ankit/jira-helper","description":null,"source":"github","installs":900}\
            ],"skills-sh":false}
            """
        let search = loaded(json, repositories: [("packagist", true), ("github", true)])
        search.sourceFilter = "github"
        #expect(search.filteredResults.map(\.name) == ["github:ankit/jira-helper"], "github is allowed")
        search.store.preload(snapshot: DesignFixtures.api)
        #expect(search.filteredResults.isEmpty, "api blocks github")
        #expect(search.sourceChips.last == Chip(name: "github", kind: .github, count: 0), "the active chip stays")
        #expect(search.totalResultCount == 2)
        #expect(search.isFilterEmpty)
    }

    // MARK: - Filtered results

    @Test func noFilterShowsEveryResultSortedByInstalls() {
        let search = loaded()
        #expect(search.sourceFilter == nil)
        #expect(search.filteredResults == search.sortedResults)
        #expect(search.filteredResults.count == search.totalResultCount)
    }

    @Test func aFilterKeepsOnlyItsSourceStillSortedByInstalls() {
        let search = loaded()
        search.sourceFilter = "packagist"
        #expect(search.filteredResults.map(\.installs) == [4100, 2200])
        #expect(search.totalResultCount == 7, "the total ignores the filter")
        #expect(search.isSortedByInstalls)
    }

    @Test func sortedByInstallsIsFalseWhenTheFilterLeavesOnlyUncountedResults() {
        let search = loaded(Self.uncountedAcmeJSON)
        #expect(search.isSortedByInstalls)
        search.sourceFilter = "acme"
        #expect(search.filteredResults.count == 2)
        #expect(!search.isSortedByInstalls)
    }

    // MARK: - Selection

    @Test func aFilterThatHidesTheSelectionClearsIt() {
        let search = loaded(selection: "acme/jira-triage")
        search.sourceFilter = "packagist"
        #expect(search.selection == nil)
        #expect(search.selectedResult == nil)
    }

    @Test func aFilterThatShowsTheSelectionKeepsIt() {
        let search = loaded(selection: "acme/jira-triage")
        search.sourceFilter = "acme"
        #expect(search.selection == "acme/jira-triage")
        #expect(search.selectedResult?.name == "acme/jira-triage")
    }

    @Test func aFilterNeverSelectsAResult() {
        let search = loaded()
        search.sourceFilter = "skills.sh"
        #expect(search.filteredResults.count == 1)
        #expect(search.selection == nil && search.selectedResult == nil)
    }

    @Test func theSelectedResultIsLookedUpInTheFilteredResults() {
        let search = loaded(selection: "acme/jira-triage")
        #expect(search.selectedResult?.name == "acme/jira-triage")
        search.sourceFilter = "skills.sh"
        #expect(search.selectedResult == nil)
    }

    @Test func aFilterKeepsATypedSourceSelection() {
        let search = search()
        search.preload(query: "acme/jira-triage", results: .idle, selection: "acme/jira-triage")
        search.sourceFilter = "packagist"
        #expect(search.selection == "acme/jira-triage")
    }

    @Test(.timeLimit(.minutes(1))) func aNewDocumentThatHidesTheSelectionClearsIt() async {
        await client.json(Self.searchJira, in: scope, Self.mixedJSON)
        await client.json(Self.searchJira, in: scope, Self.pdfJSON)
        let search = search()
        search.query = "jira"
        await search.searchTask?.value
        search.selection = "acme/jira-triage"
        search.retry()
        await search.searchTask?.value
        #expect(search.sortedResults.count == 2, "the second document landed")
        #expect(search.selection == nil)
        #expect(search.selectedResult == nil)
    }

    // MARK: - Across queries

    @Test(.timeLimit(.minutes(1))) func theFilterSurvivesANewQuery() async {
        await client.json(Self.searchJira, in: scope, Self.mixedJSON)
        await client.json(Self.searchPdf, in: scope, Self.pdfJSON)
        let search = search(debounce: .milliseconds(50))
        search.query = "jira"
        await search.searchTask?.value
        search.sourceFilter = "skills.sh"
        search.query = "p"
        search.query = "pdf"
        await search.searchTask?.value
        #expect(search.sourceFilter == "skills.sh")
        #expect(search.filteredResults.map(\.name) == ["github:anthropics/skills/pdf"])
        #expect(!search.isFilterEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func aNewQueryWithoutResultsForTheFilterIsAnEmptyFilterThatKeepsItsChip() async {
        await client.json(Self.searchJira, in: scope, Self.mixedJSON)
        await client.json(Self.searchPdf, in: scope, Self.pdfJSON)
        let search = search()
        search.query = "jira"
        await search.searchTask?.value
        search.sourceFilter = "internal"
        search.query = "pdf"
        await search.searchTask?.value
        #expect(search.sourceFilter == "internal")
        #expect(search.filteredResults.isEmpty && search.totalResultCount == 2)
        #expect(search.isFilterEmpty)
        #expect(search.sourceChips.last == Chip(name: "internal", kind: .custom("internal"), count: 0))
    }

    @Test func anEmptyFilterNeedsALoadedDocumentAndAFilter() {
        let search = loaded()
        #expect(!search.isFilterEmpty, "no filter")
        search.sourceFilter = "skills.sh"
        #expect(!search.isFilterEmpty, "skills.sh has a result")
        let idle = self.search()
        idle.sourceFilter = "skills.sh"
        #expect(!idle.isFilterEmpty, "nothing loaded")
    }

    @Test func aNewSheetStartsWithoutAFilter() {
        #expect(search().sourceFilter == nil)
    }

    // MARK: - Copy

    @Test func resultCountReadsShownOfTotalOnlyWhenFiltered() {
        #expect(AddSkillCopy.results(shown: 20, total: 20) == "20 results")
        #expect(AddSkillCopy.results(shown: 1, total: 1) == "1 result")
        #expect(AddSkillCopy.results(shown: 3, total: 20) == "3 of 20 results")
    }

    @Test func emptyFilterCopyNamesTheSourceAndTheResultsElsewhere() {
        #expect(AddSkillCopy.noResultsFrom("Packagist") == "No results from Packagist")
        #expect(AddSkillCopy.resultsElsewhere(20) == "20 results from other sources.")
        #expect(AddSkillCopy.resultsElsewhere(1) == "1 result from another source.")
        #expect(AddSkillCopy.resultsElsewhere(0) == "Nothing matched in any source.")
        #expect(EmptyCopy.showAll == "Show All")
    }

    // MARK: - Chip bar

    @Test func aChipIsActiveForItsFilterIgnoringCaseAndATapOnTheActiveChipClearsIt() {
        let acme = Chip(name: "acme", kind: .custom("acme"), count: 2)
        #expect(SourceFilterBar.isActive(acme, filter: "ACME") && !SourceFilterBar.isActive(acme, filter: nil))
        #expect(SourceFilterBar.filter(afterTapping: acme, current: nil) == "acme")
        #expect(SourceFilterBar.filter(afterTapping: acme, current: "packagist") == "acme")
        #expect(SourceFilterBar.filter(afterTapping: acme, current: "acme") == nil)
    }

    @Test func aChipWithoutResultsIsDisabledUnlessActive() {
        let github = Chip(name: "github", kind: .github, count: 0)
        #expect(!SourceFilterBar.isEnabled(github, isActive: false))
        #expect(SourceFilterBar.isEnabled(github, isActive: true))
        #expect(SourceFilterBar.isEnabled(Chip(name: "packagist", kind: .packagist, count: 1), isActive: false))
    }

    @Test func chipAccessibilityReadsTheCountAndTheSource() {
        #expect(SourceFilterBar.accessibilityValue(20) == "20 results")
        #expect(SourceFilterBar.accessibilityValue(1) == "1 result")
        #expect(AddSkillCopy.filterHint("skills.sh") == "Shows only results from skills.sh")
        #expect(AddSkillCopy.filterLabel == "Filter by source")
    }

    @Test func theEmptyFilterNamesItsChipsSourceLabel() {
        let search = loaded()
        search.sourceFilter = "Packagist"
        #expect(SourceFilterBar.label(of: "Packagist", in: search.sourceChips) == "Packagist")
        #expect(SourceFilterBar.label(of: "acme", in: search.sourceChips) == "acme")
        #expect(SourceFilterBar.label(of: "skills.sh", in: []) == "skills.sh")
    }

    @Test func theSummaryShowsForResultsOrAnActiveFilter() {
        let empty = DesignFixtures.decode(SearchDocument.self, json: #"{"results":[],"skills-sh":true}"#)
        let some = DesignFixtures.decode(SearchDocument.self, json: Self.pdfJSON)
        #expect(AddSkillSheet.showsSummary(results: .loaded(some), filter: nil))
        #expect(!AddSkillSheet.showsSummary(results: .loaded(empty), filter: nil))
        #expect(AddSkillSheet.showsSummary(results: .loaded(empty), filter: "packagist"))
        #expect(!AddSkillSheet.showsSummary(results: .searching, filter: "packagist"))
        #expect(!AddSkillSheet.showsSummary(results: .idle, filter: nil))
    }
}
