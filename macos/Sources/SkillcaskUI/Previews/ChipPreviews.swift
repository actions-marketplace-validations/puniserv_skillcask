import SkillcaskDomain
import SwiftUI

extension PreviewRegistry {
    /// The filter bar with the api scope's counts plus one idle and one active chip, and the pills:
    /// sources in board order, the agent pill and two reach groups from the pdf audit row.
    static let chips: [Entry] = [
        Entry(id: "P2-3", state: "chips", size: CGSize(width: 640, height: 150)) { AnyView(ChipsSample()) },
        Entry(id: "P2-3", state: "pills", size: CGSize(width: 640, height: 220)) { AnyView(PillsSample()) },
    ]
}

/// The list header's filter bar bound to the api scope's attention, then a default and an active chip.
private struct ChipsSample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            FilterChipBarSample(selection: .needsAttention, attention: DesignFixtures.api.attention)
            HStack(spacing: Spacing.inline) {
                FilterChip("Updates", count: 2, countSeverity: .update, isActive: false) {}
                FilterChip("Updates", count: 2, countSeverity: .update, isActive: true) {}
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceWindow)
    }
}

/// Source pills in the board's order, the agent pill and the pdf row's reach groups (an empty group proves
/// it hides).
private struct PillsSample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Pill(source: SourceKind(parsing: "packagist"))
                Pill(source: SourceKind(parsing: "github:anthropics/skills"))
                Pill(source: .git)
                Pill(source: .skillsSh)
                Pill(source: SourceKind(parsing: "acme"))
            }
            HStack(spacing: Spacing.s) {
                Pill(source: .project)
                Pill(source: .local)
                Pill(blocked: .github)
                Pill("Claude Code", style: .agent)
            }
            if let pdf = DesignFixtures.apiAudit.skills.first(where: { $0.skill == "pdf" }) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ChipGroup(
                        label: ReachCopy.label(.commands), items: pdf.commands, labelWidth: chipGroupPreviewLabelWidth)
                    ChipGroup(
                        label: ReachCopy.label(.network), items: pdf.network, labelWidth: chipGroupPreviewLabelWidth)
                    ChipGroup(label: ReachCopy.label(.env), items: pdf.env, labelWidth: chipGroupPreviewLabelWidth)
                }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceWindow)
    }
}
