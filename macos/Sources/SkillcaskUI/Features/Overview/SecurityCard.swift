import SkillcaskDomain
import SwiftUI

/// The Security card (Overview): the rows changed on disk (rule `modified`, the error document glyph) and every
/// text finding (the warning triangle), one line each with the skill's name; Show in list in the header. Clean,
/// it collapses to `Security · no findings  Nothing changed on disk` (Overview-States Healthy).
struct SecurityCard: View {
    let snapshot: ScopeSnapshot
    let onTitleTap: () -> Void

    static func changed(_ snapshot: ScopeSnapshot) -> [SkillEntry] {
        snapshot.entries.filter { $0.health == .changedOnDisk }
    }

    static func findings(_ snapshot: ScopeSnapshot) -> [OverviewCopy.Line] {
        snapshot.entries.flatMap { entry in
            entry.findings.filter(\.kind.isTextFinding)
                .map {
                    OverviewCopy.Line(
                        lead: .name(entry.name),
                        words: OverviewCopy.finding($0.kind, message: $0.message, line: $0.line))
                }
        }
    }

    /// Nothing changed on disk and no finding.
    static func isCollapsed(_ snapshot: ScopeSnapshot) -> Bool {
        changed(snapshot).isEmpty && findings(snapshot).isEmpty
    }

    var body: some View {
        let changed = Self.changed(snapshot)
        let findings = Self.findings(snapshot)
        let isClean = Self.isCollapsed(snapshot)
        CardContainer(
            title: OverviewCopy.security,
            status: isClean ? OverviewCopy.securityStatus(changed: 0, findings: 0) : nil,
            severity: isClean ? .ok : .warning, summary: isClean ? OverviewCopy.nothingChanged : nil,
            isCollapsed: isClean, onTitleTap: onTitleTap
        ) {
            if !isClean {
                Button(OverviewCopy.showInList, action: onTitleTap)
                    .buttonStyle(.plain)
                    .font(Font.Token.calloutMedium)
                    .foregroundStyle(Color.accent)
            }
        } content: {
            VStack(alignment: .leading, spacing: Spacing.s) {
                // Under the title, like Health's "Repaired 2 items", so the header stays on one line.
                Text(OverviewCopy.securityStatus(changed: changed.count, findings: findings.count))
                    .font(Font.Token.captionSemibold)
                    .foregroundStyle(Color.textSecondary)
                ForEach(changed) { entry in
                    OverviewLine(
                        OverviewCopy.Line(lead: .name(entry.name), words: OverviewCopy.changedOnDisk),
                        glyph: .symbol("doc.badge.ellipsis", .error))
                }
                ForEach(Array(findings.enumerated()), id: \.offset) { _, line in
                    OverviewLine(line, glyph: .symbol("exclamationmark.triangle", .warning))
                }
            }
        }
    }
}
