import SkillcaskCore
import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// P3-6: the detail column (header and Security tab) at 720 × 900, one state per Security and Security-States
    /// panel: `findings` (my-notes, the Security board), `clean` (commit-message), `changedOnDisk` (jira-syntax
    /// with a `modified` finding: a package skill, so Reinstall from lock shows), `notInstalled` (sql-review with
    /// the CLI's `modified` / `not installed` finding; no board draws it), `reachOnly` (pdf), and `notAudited`
    /// (caveman as a 0.9.1 `audit` leaves it: no row, Q7). The CLI reports `modified` for locked skills only, so
    /// no hand-written changed-on-disk state is rendered.
    /// Composed from `DetailHeader` and `SecurityTab` as `SkillDetailView` composes them, so no store is needed.
    static let security: [Entry] = [
        entry("findings") { SecuritySample(entry: DesignFixtures.myNotes) },
        entry("clean") { SecuritySample(entry: DesignFixtures.commitMessage) },
        entry("changedOnDisk") { SecuritySample(entry: modifiedJiraSyntax) },
        entry("notInstalled") { SecuritySample(entry: notInstalledSqlReview) },
        entry("reachOnly") { SecuritySample(entry: DesignFixtures.pdf) },
        entry("notAudited") { SecuritySample(entry: unauditedCaveman) },
    ]

    private static func entry(_ state: String, _ make: @escaping @MainActor @Sendable () -> SecuritySample) -> Entry {
        Entry(id: "P3-6", state: state, size: CGSize(width: 720, height: 900)) { AnyView(make()) }
    }
}

/// jira-syntax (a package skill) changed on disk: deploy-checklist's `modified` finding on jira-syntax's row.
private let modifiedJiraSyntax: SkillEntry = {
    let jira = DesignFixtures.jiraSyntax
    return SkillEntry(
        id: jira.id, name: jira.name, kind: jira.kind, source: jira.source, version: jira.version, state: .modified,
        health: .changedOnDisk, update: nil, findings: DesignFixtures.deployChecklist.findings, path: jira.path,
        description: jira.description, reach: jira.reach)
}()

/// sql-review (a package skill the status fixture reports `not installed`) as `audit` reports it: a `modified`
/// finding with the message `not installed` (`src/commands.rs` `audit()`).
private let notInstalledSqlReview: SkillEntry = {
    let sql = DesignFixtures.sqlReview
    let json = #"{"rule":"modified","path":".agents/skills/sql-review","line":null,"message":"not installed"}"#
    let finding = DesignFixtures.decode(AuditDocument.Finding.self, json: json)
    return SkillEntry(
        id: sql.id, name: sql.name, kind: sql.kind, source: sql.source, version: sql.version, state: sql.state,
        health: sql.health, update: nil, findings: [finding], path: ".agents/skills/sql-review",
        description: sql.description, reach: sql.reach)
}()

/// caveman as the 0.9.1 CLI reports it: `audit` lists no not managed skill, so the row has no reach and no findings.
private let unauditedCaveman: SkillEntry = {
    let caveman = DesignFixtures.caveman
    return SkillEntry(
        id: caveman.id, name: caveman.name, kind: caveman.kind, source: caveman.source, version: caveman.version,
        state: caveman.state, health: caveman.health, update: caveman.update, findings: [], path: caveman.path,
        description: caveman.description, reach: nil)
}()

/// One detail column over fixture data: the header with the Security tab selected and the tab's body.
private struct SecuritySample: View {
    let entry: SkillEntry
    @State private var tab = DetailTab.security

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(
                entry: entry, isOffline: false, selectedTab: $tab,
                requiredBy: DesignFixtures.api.requirerSkills(of: entry))
            SecurityTab(content: SecurityContent(entry: entry), checkedAt: DesignFixtures.api.checkedAt)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.surfaceWindow)
    }
}
