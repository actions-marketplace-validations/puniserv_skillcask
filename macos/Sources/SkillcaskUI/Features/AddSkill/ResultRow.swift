import SkillcaskCore
import SkillcaskDomain
import SwiftUI

/// One search result (AddSkill board `.res`): the name in mono, its source pill, the Installed marker when the
/// package is already in this scope's lock, the install count trailing, and the description under it. A result
/// from a repository the policy blocks is dimmed with "Blocked by policy" in place of the count. Selected, the row
/// takes the system accent and white text, as `SkillRow` does.
struct ResultRow: View {
    let result: SearchDocument.Result
    /// The skills the result's package already installs here; empty when it is not installed.
    let installedAs: [String]
    let isBlocked: Bool
    /// The row is the list's selection (the list's own prominence does not reach an offscreen render).
    var isSelected = false
    /// The scope is My Skills: "Already in My Skills as …".
    var isPersonal = false

    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs / 2) {
            HStack(spacing: Spacing.s) {
                Text(result.name)
                    .font(Font.Token.mono)
                    .fontWeight(.semibold)
                    .foregroundStyle(primaryColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // The name wins the row's width (AddSkill board): the install count gives way first.
                    .layoutPriority(2)
                if let source {
                    Pill(source: source)
                        .layoutPriority(1)
                }
                if !installedAs.isEmpty {
                    InstalledMarker(emphasized: emphasized, isPersonal: isPersonal)
                        .layoutPriority(1)
                }
                Spacer(minLength: Spacing.xs)
                if let trailing {
                    Text(trailing)
                        .font(Font.Token.caption)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            if let description {
                Text(description)
                    .font(Font.Token.callout)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Spacing.inline)
        .padding(.horizontal, Spacing.xs)
        .opacity(isBlocked ? ResultsColumn.blockedOpacity : 1)
        .environment(\.backgroundProminence, emphasized ? .increased : .standard)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived

    private var source: SourceKind? {
        result.source.map(SourceKind.init(parsing:))
    }

    private var trailing: String? {
        if isBlocked {
            return AddSkillCopy.blocked
        }
        return result.installs.map(AddSkillCopy.installs)
    }

    private var description: String? {
        if isBlocked, let source {
            return AddSkillCopy.blockedDescription(SourceCopy.label(source))
        }
        let parts = [
            result.description, installedAs.isEmpty ? nil : AddSkillCopy.alreadyIn(installedAs, personal: isPersonal),
        ]
        .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var emphasized: Bool {
        SkillRow.usesSelectedStyle(
            isSelected: isSelected || prominence == .increased, active: controlActiveState != .inactive)
    }

    private var primaryColor: Color {
        emphasized ? SkillRow.selectedPrimary : Color.textPrimary
    }

    private var secondaryColor: Color {
        emphasized ? SkillRow.selectedSecondary : Color.textSecondary
    }
}

/// The board's green "Installed" pill (`--ok-tint` behind `--ok-t`); on a selected row the white pill of `Pill`.
private struct InstalledMarker: View {
    let emphasized: Bool
    let isPersonal: Bool

    var body: some View {
        Text(AddSkillCopy.installed)
            .font(Font.Token.captionMedium)
            .foregroundStyle(emphasized ? Pill.onSelectionText : Color.statusOkText)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.inline)
            .frame(height: Size.pill)
            .background(
                emphasized ? Pill.onSelectionFill : Color.statusOkTint,
                in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
            )
            .accessibilityHint(AddSkillCopy.installedHint(personal: isPersonal))
    }
}
