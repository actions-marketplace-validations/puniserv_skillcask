import SkillcaskDomain
import SwiftUI

/// The Health card (Overview, Health-States): `doctor`'s problems, warnings and repaired items as the boards'
/// sentences with what fixes each, the passed count as a disclosure of the passed checks, the Repair and Sync
/// buttons in the header and the footnote. Healthy, it collapses to `Health · all good  8 checks passed`. The
/// title opens the results popover (S12, Health-States "opens from the Health card title"); before doctor has
/// answered there is nothing to show, and the title opens the filtered list as the other cards' titles do.
struct HealthCard: View {
    let snapshot: ScopeSnapshot
    let isBusy: Bool
    let onRepair: () -> Void
    let onSync: () -> Void
    let onCheckAgain: () -> Void
    /// The title without a doctor answer.
    let onTitleTap: () -> Void

    @State private var showsPassed = false
    @State private var showsResults = false

    private var doctor: ScopeSnapshot.Doctor? { snapshot.doctor }

    /// The Overview-States Healthy rule: doctor answered with nothing open and nothing repaired.
    static func isCollapsed(_ snapshot: ScopeSnapshot) -> Bool {
        guard let doctor = snapshot.doctor else { return false }
        return doctor.problems.isEmpty && doctor.warnings.isEmpty && doctor.fixed.isEmpty
    }

    /// The header dot: error for a problem, warning for a warning, ok otherwise; none before doctor answers.
    static func severity(_ snapshot: ScopeSnapshot) -> Severity? {
        guard let doctor = snapshot.doctor else { return nil }
        if !doctor.problems.isEmpty { return .error }
        if !doctor.warnings.isEmpty { return .warning }
        return .ok
    }

    private var status: String {
        guard let doctor else { return OverviewCopy.healthUnknown }
        return OverviewCopy.healthStatus(problems: doctor.problems.count, warnings: doctor.warnings.count)
    }

    /// The trailing header text of the collapsed card: `8 checks passed`.
    private var summary: String? {
        guard let doctor, Self.isCollapsed(snapshot) else { return nil }
        return OverviewCopy.checksPassed(doctor.passed.count)
    }

    /// `Repaired 2 items`: under the title rather than beside Repair and Sync, so it stays on one line.
    private var repairedLine: String? {
        guard let doctor, !doctor.fixed.isEmpty else { return nil }
        return OverviewCopy.repaired(doctor.fixed.count)
    }

    var body: some View {
        CardContainer(
            title: OverviewCopy.health, status: status, severity: Self.severity(snapshot), summary: summary,
            isCollapsed: Self.isCollapsed(snapshot), onTitleTap: titleTap
        ) {
            if !Self.isCollapsed(snapshot) {
                HStack(spacing: Spacing.inline) {
                    Button(OverviewCopy.repair, systemImage: "wrench.and.screwdriver", action: onRepair)
                        .labelStyle(.titleOnly)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isBusy || !(doctor?.canRepair ?? true))
                    Button(OverviewCopy.sync, systemImage: "arrow.triangle.2.circlepath", action: onSync)
                        .labelStyle(.titleOnly)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accent)
                        .controlSize(.small)
                        .disabled(isBusy || !ToolbarRules.canSync(snapshot))
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: Spacing.s) {
                if let repairedLine {
                    Text(repairedLine)
                        .font(Font.Token.captionSemibold)
                        .foregroundStyle(Color.textSecondary)
                }
                if let doctor {
                    ForEach(Array(doctor.problemItems.enumerated()), id: \.offset) { _, item in
                        OverviewLine(
                            OverviewCopy.problem(item, remedy: doctor.remedy(of: item)),
                            glyph: .symbol("xmark.circle", .error))
                    }
                    ForEach(Array(doctor.warningItems.enumerated()), id: \.offset) { _, item in
                        OverviewLine(
                            OverviewCopy.problem(item, remedy: doctor.remedy(of: item)),
                            glyph: .symbol("exclamationmark.triangle", .warning))
                    }
                    ForEach(Array(doctor.fixedItems.enumerated()), id: \.offset) { _, item in
                        OverviewLine(OverviewCopy.fixed(item), glyph: .symbol("checkmark.circle", .update))
                    }
                    passed(doctor)
                }
                Text(OverviewCopy.healthFootnote)
                    .font(Font.Token.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Anchored on the title's bounds (`CardTitleAnchor`), so the arrow points at what was clicked.
        .overlayPreferenceValue(CardTitleAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let title = proxy[anchor]
                    Color.clear
                        .frame(width: title.width, height: title.height)
                        // Laid out at the title's frame (not drawn there by an offset), so the popover's anchor is it.
                        .position(x: title.midX, y: title.midY)
                        .allowsHitTesting(false)
                        .popover(isPresented: $showsResults, arrowEdge: .bottom) { results }
                }
            }
        }
    }

    @ViewBuilder private var results: some View {
        if let doctor {
            HealthPopover(
                report: .resolve(doctor),
                when: RunningCopy.when(snapshot.checkedAt, repaired: !doctor.fixed.isEmpty), isBusy: isBusy,
                canSync: ToolbarRules.canSync(snapshot), onRepair: onRepair, onSync: onSync,
                onCheckAgain: onCheckAgain)
        }
    }

    /// The popover once doctor answered, else the caller's list filter.
    private func titleTap() {
        if doctor == nil {
            onTitleTap()
        } else {
            showsResults = true
        }
    }

    // MARK: - Subviews

    /// `⌄ 6 checks passed`: a disclosure of the passed checks (the board's chevron link).
    @ViewBuilder private func passed(_ doctor: ScopeSnapshot.Doctor) -> some View {
        if !doctor.passed.isEmpty {
            Button {
                showsPassed.toggle()
            } label: {
                OverviewLine(
                    OverviewCopy.checksPassed(doctor.passed.count),
                    glyph: .symbol(showsPassed ? "chevron.up" : "chevron.down", nil), isQuiet: true
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(OverviewCopy.showPassedHint)
            if showsPassed {
                ForEach(Array(doctor.passedItems.enumerated()), id: \.offset) { _, item in
                    OverviewLine(OverviewCopy.passed(item), glyph: .symbol("checkmark", .ok), isQuiet: true)
                }
            }
        }
    }
}
