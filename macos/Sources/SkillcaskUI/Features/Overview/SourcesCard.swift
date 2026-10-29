import SkillcaskCore
import SkillcaskDomain
import SwiftUI

/// The Sources card (Overview): `status.repositories` as a four-column table of name, type, address and whether
/// the policy allows it, then the footnote naming what a blocked source means. No dot: sources are facts, not a
/// state. In a quiet project (Overview-States Healthy) it is one `packagist  Allowed` line per source.
struct SourcesCard: View {
    let snapshot: ScopeSnapshot
    /// Overview-States Healthy: the compact one-line form.
    let isCompact: Bool

    /// The footnote under the table; nil when every source is allowed.
    static func footnote(_ snapshot: ScopeSnapshot) -> String? {
        OverviewCopy.blockedFootnote(
            snapshot.repositories.filter { !$0.allowed }.map(OverviewCopy.blockedName),
            policy: snapshot.policy.first { $0.kind == .allowSources })
    }

    var body: some View {
        CardContainer(title: OverviewCopy.sources) {
            if isCompact {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(snapshot.repositories, id: \.name) { repository in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Text(repository.name)
                                .font(Font.Token.monoSmall)
                                .foregroundStyle(Color.textPrimary)
                            policy(repository)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    CardTable(
                        headers: [
                            OverviewCopy.sourceName, OverviewCopy.sourceType, OverviewCopy.sourceAddress,
                            OverviewCopy.sourcePolicy,
                        ],
                        rows: snapshot.repositories.map(row))
                    if let footnote = Self.footnote(snapshot) {
                        Text(footnote)
                            .font(Font.Token.caption)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func policy(_ repository: StatusDocument.Repository) -> some View {
        Text(repository.allowed ? OverviewCopy.allowed : OverviewCopy.blocked)
            .font(Font.Token.calloutMedium)
            .foregroundStyle(Color.statusText(repository.allowed ? .ok : .warning))
    }

    private func row(_ repository: StatusDocument.Repository) -> [CardTable.Cell] {
        [
            .mono(repository.name), .text(OverviewCopy.sourceType(repository)),
            .address(OverviewCopy.sourceAddress(repository)),
            repository.allowed ? .status(OverviewCopy.allowed, .ok) : .status(OverviewCopy.blocked, .warning),
        ]
    }
}
