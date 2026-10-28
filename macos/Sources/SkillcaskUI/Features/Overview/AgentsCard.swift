import SkillcaskDomain
import SwiftUI

/// The Agents card (Overview): `status.targets` as agent, directory and where it was set, then how many skills
/// are linked into them and, from `doctor`, which agent has a wrong link. In a quiet project (Overview-States
/// Healthy) it is one `Claude Code  .claude/skills  skills.toml` line per agent.
struct AgentsCard: View {
    let snapshot: ScopeSnapshot
    /// Overview-States Healthy: the compact one-line form.
    let isCompact: Bool

    /// Agent, directory: the CLI prints them as two parallel lists.
    static func targets(_ snapshot: ScopeSnapshot) -> [(agent: String, directory: String)] {
        guard let targets = snapshot.targets else { return [] }
        return targets.entries.enumerated()
            .map { index, entry in
                (entry, index < targets.dirs.count ? targets.dirs[index] : "")
            }
    }

    /// The skills that have no links in the agent folders: not installed or not linked by `status`, or reported
    /// as not installed by `doctor` (whose per-target `link missing` lines Health lists). Sorted by name.
    static func unlinked(_ snapshot: ScopeSnapshot) -> [String] {
        let missing = snapshot.doctor?.missingSkills ?? []
        return snapshot.entries
            .filter { entry in
                switch entry.health {
                case .notInstalled, .notLinked: true
                default: missing.contains(entry.name)
                }
            }
            .map(\.name)
            .sorted()
    }

    /// `12 skills are linked into both. Not linked: jira-syntax, sql-review. One Cursor link is wrong — see
    /// Health.` The linked count leaves out `unlinked`, so it agrees with doctor's missing links.
    static func footnote(_ snapshot: ScopeSnapshot) -> String {
        let targets = targets(snapshot)
        let unlinked = unlinked(snapshot)
        var sentences = [OverviewCopy.linked(skills: snapshot.entries.count - unlinked.count, agents: targets.count)]
        if !unlinked.isEmpty {
            sentences.append(OverviewCopy.notLinked(unlinked))
        }
        for target in targets {
            let broken = snapshot.doctor?.brokenLinks(in: target.directory) ?? 0
            if broken > 0 {
                sentences.append(OverviewCopy.brokenLinks(broken, agent: ShellCopy.agentName(target.agent)))
            }
        }
        return sentences.joined(separator: " ")
    }

    var body: some View {
        let targets = Self.targets(snapshot)
        let from = snapshot.targets?.from ?? ""
        CardContainer(title: OverviewCopy.agents, isCollapsed: targets.isEmpty) {
            if isCompact {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(targets, id: \.agent) { target in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Text(ShellCopy.agentName(target.agent))
                                .font(Font.Token.calloutMedium)
                                .foregroundStyle(Color.textPrimary)
                            Text(target.directory)
                                .font(Font.Token.monoSmall)
                                .foregroundStyle(Color.textSecondary)
                            Spacer(minLength: Spacing.s)
                            Text(from)
                                .font(Font.Token.monoSmall)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    CardTable(
                        headers: [OverviewCopy.agent, OverviewCopy.directory, OverviewCopy.setIn],
                        rows: targets.map { target in
                            [
                                .medium(ShellCopy.agentName(target.agent)), .monoSecondary(target.directory),
                                .mono(from),
                            ]
                        })
                    Text(Self.footnote(snapshot))
                        .font(Font.Token.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
