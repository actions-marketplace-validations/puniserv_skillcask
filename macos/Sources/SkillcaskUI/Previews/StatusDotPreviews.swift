import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// P2-1: the five-state vocabulary as the Components board's "Status dot + label" region, and every `Health`
    /// case through `Labels.health`, from the design fixtures where one carries it.
    static let statusDot: [Entry] = [
        Entry(id: "P2-1", state: "vocabulary", size: CGSize(width: 620, height: 150)) {
            AnyView(VocabularyPreview())
        },
        Entry(id: "P2-1", state: "labels", size: CGSize(width: 620, height: 560)) {
            AnyView(HealthLabelsPreview())
        },
    ]
}

/// The board region: a section card with its heading, then the six examples wrapped on two lines.
private struct VocabularyPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text("Status dot + label").font(Font.Token.bodyEmphasis).foregroundStyle(Color.textPrimary)
                Text("8 pt dot, label in status.text; never colour alone")
                    .font(Font.Token.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.xxl) {
                    StatusLabel(.installed)
                    StatusLabel(.updateAvailable(from: "1.2.0", to: "1.4.0"))
                    StatusLabel(.notManaged)
                    StatusLabel(.changedOnDisk)
                }
                HStack(spacing: Spacing.xxl) {
                    StatusLabel(.neutral, Labels.requiredBy(["caveman"]))
                    StatusLabel.notSetUp(Labels.unknown)
                    StatusLabel.notSetUp()
                }
            }
        }
        .padding(.vertical, Size.cardPaddingH)
        .padding(.horizontal, Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceWindow, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Color.separator))
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceWindow)
    }
}

/// Every `Health` case as `Labels.health` words it: the fixture entry that carries the case where one exists, a
/// bare value for the five cases no board row shows (project, local, not linked, needs sync, duplicate).
private struct HealthLabelsPreview: View {
    struct Row: Identifiable, Sendable {
        let id: String
        let health: Health
        let source: String
    }

    static let rows: [Row] = [
        Row(id: "installed", health: DesignFixtures.commitMessage.health, source: "commit-message"),
        Row(id: "projectSkill", health: .projectSkill, source: "value"),
        Row(id: "localSkill", health: .localSkill, source: "value"),
        Row(id: "updateAvailable", health: DesignFixtures.pdf.health, source: "pdf"),
        Row(id: "notManaged", health: DesignFixtures.caveman.health, source: "caveman"),
        Row(id: "notLinked", health: .notLinked, source: "value"),
        Row(id: "findings(2)", health: DesignFixtures.myNotes.health, source: "my-notes"),
        Row(id: "findings(1)", health: DesignFixtures.standupSummary.health, source: "standup-summary (personal)"),
        Row(id: "cooldown", health: DesignFixtures.jiraCommunication.health, source: "jira-communication"),
        Row(id: "notInstalled", health: DesignFixtures.jiraSyntax.health, source: "jira-syntax"),
        Row(id: "changedOnDisk", health: DesignFixtures.deployChecklist.health, source: "deploy-checklist"),
        Row(id: "needsSync", health: .needsSync(reason: "not in skills.lock"), source: "value"),
        Row(id: "duplicate", health: .duplicate("skill \"x\" is provided by both a/b and c/d"), source: "value"),
        Row(id: "unknown(blocked by policy)", health: DesignFixtures.testWriter.health, source: "test-writer"),
        Row(id: "unknown(abandoned)", health: DesignFixtures.legacyLint.health, source: "legacy-lint"),
        Row(id: "unknown(tag moved)", health: .unknown("tag moved"), source: "value"),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.s) {
            GridRow {
                Text("Labels.health").font(Font.Token.captionMedium).foregroundStyle(Color.textSecondary)
                Text("Health").font(Font.Token.captionMedium).foregroundStyle(Color.textSecondary)
                Text("Severity").font(Font.Token.captionMedium).foregroundStyle(Color.textSecondary)
                Text("Fixture").font(Font.Token.captionMedium).foregroundStyle(Color.textSecondary)
            }
            ForEach(Self.rows) { row in
                GridRow {
                    StatusLabel(row.health)
                    Text(row.id).font(Font.Token.monoSmall).foregroundStyle(Color.textSecondary)
                    Text(Labels.severity(row.health.severity))
                        .font(Font.Token.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(row.source).font(Font.Token.caption).foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceWindow)
    }
}
