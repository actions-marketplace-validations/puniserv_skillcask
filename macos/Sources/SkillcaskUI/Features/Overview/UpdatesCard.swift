import SkillcaskDomain
import SwiftUI

/// The Updates card (Overview): one row per package with a newer version inside its range (`pdf 1.2.0 → 1.4.0`
/// and Review changes…), then the quiet lines for cooldowns and versions outside the range; Review All… in the
/// header. Nothing to show, it collapses to `Updates · none  Everything is current` (Overview-States Healthy).
struct UpdatesCard: View {
    let snapshot: ScopeSnapshot
    let onTitleTap: () -> Void
    let onReviewAll: () -> Void
    let onReview: (String) -> Void

    /// The board's `width: 120px` name column of an update row; narrower cards truncate the names first.
    static let nameWidth: CGFloat = 120

    private var available: [Update] { snapshot.availableUpdates }

    private var cooldowns: [Update] { Self.cooldowns(snapshot) }

    private var outside: [Update] { Self.outside(snapshot) }

    static func cooldowns(_ snapshot: ScopeSnapshot) -> [Update] {
        (snapshot.updates ?? []).filter { $0.available == nil && $0.eligible != nil }
    }

    static func outside(_ snapshot: ScopeSnapshot) -> [Update] {
        (snapshot.updates ?? []).filter { $0.available == nil && $0.eligible == nil && $0.outsideRange != nil }
    }

    /// Nothing to list: no update, no cooldown, nothing outside the range (or not checked yet).
    /// One update row: the skill, its transition and the package Review changes… opens.
    struct Row: Hashable {
        let name: String
        let from: String
        let to: String
        let package: String
    }

    /// One row per skill with an update inside its range, in the list's order (pdf, then review-pr), named by
    /// skill as the board does; a skill of the package that cannot take the update (test-writer, blocked by
    /// policy) gets no row. A package with no such skill here keeps one row named by the package.
    static func rows(_ snapshot: ScopeSnapshot) -> [Row] {
        var rows: [Row] = []
        var covered: Set<String> = []
        for entry in snapshot.entries {
            guard case .updateAvailable(let from, let to) = entry.health, let package = entry.package else { continue }
            rows.append(Row(name: entry.name, from: from, to: to, package: package))
            covered.insert(package)
        }
        for update in snapshot.availableUpdates where !covered.contains(update.package) {
            if let transition = update.available {
                rows.append(
                    Row(name: update.package, from: transition.from, to: transition.to, package: update.package))
            }
        }
        return rows
    }

    static func isCollapsed(_ snapshot: ScopeSnapshot) -> Bool {
        snapshot.availableUpdates.isEmpty && cooldowns(snapshot).isEmpty && outside(snapshot).isEmpty
    }

    private var severity: Severity? {
        guard snapshot.updatesChecked else { return nil }
        return available.isEmpty ? .ok : .update
    }

    private var summary: String? {
        snapshot.updatesChecked && Self.isCollapsed(snapshot) ? OverviewCopy.everythingCurrent : nil
    }

    var body: some View {
        CardContainer(
            title: OverviewCopy.updatesTitle,
            status: OverviewCopy.updatesStatus(available: available.count, checked: snapshot.updatesChecked),
            severity: severity, summary: summary, isCollapsed: Self.isCollapsed(snapshot), onTitleTap: onTitleTap
        ) {
            if !available.isEmpty {
                Button(OverviewCopy.reviewAll, systemImage: "doc.text.magnifyingglass", action: onReviewAll)
                    .labelStyle(.titleOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } content: {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(Self.rows(snapshot), id: \.name) { row in
                    self.row(row)
                }
                ForEach(cooldowns, id: \.package) { update in
                    OverviewLine(
                        OverviewCopy.cooldown(
                            names(of: update.package), update: update,
                            minimumAge: OverviewCopy.minimumAge(snapshot.policy)),
                        glyph: .dot(.warning), isQuiet: true)
                }
                ForEach(outside, id: \.package) { update in
                    if let latest = update.outsideRange {
                        OverviewLine(
                            OverviewCopy.outsideRange(names(of: update.package), version: latest),
                            glyph: .dot(.neutral), isQuiet: true)
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private func row(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(row.name)
                .font(Font.Token.calloutMedium)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: Self.nameWidth, alignment: .leading)
            Text(Labels.versionTransition(from: row.from, to: row.to))
                .font(Font.Token.monoSmall)
                .foregroundStyle(Color.textPrimary)
                .fixedSize()
            Spacer(minLength: Spacing.s)
            Button(OverviewCopy.reviewChanges) { onReview(row.package) }
                .buttonStyle(.plain)
                .font(Font.Token.calloutMedium)
                .foregroundStyle(Color.accent)
                .fixedSize()
        }
    }

    /// The skills a package provides here, as the board names rows by skill (`pdf`, not `anthropics/skills`).
    private func names(of package: String) -> [String] {
        let names = snapshot.entries.filter { $0.package == package }.map(\.name)
        return names.isEmpty ? [package] : names
    }
}
