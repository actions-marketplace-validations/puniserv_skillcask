import SkillcaskDomain
import SwiftUI

/// The version rule button and its popover (AddSkill board "Version rule · Up to next major ^4.2", Flow-F2 "Up to
/// next major (default) / Exact / Latest / Branch"), shared by the Add Skill preview and the Adopt sheet: the
/// button names the rule and the constraint it writes, the popover lists `options` as a radio group with each
/// constraint, and Branch adds a field for the branch name under the list.
///
/// The caller owns the state (`SearchStore`, the Adopt sheet's `@State`) and says which constraint each rule writes
/// (`constraint`): nil shows no constraint (the CLI's own default, which the app cannot know in advance).
struct VersionRuleControl: View {
    /// The version the rules are built from; nil when unknown (Adopt before `add` resolves).
    let base: VersionRule.Base?
    let options: [VersionRule]
    /// The rule shown and checked (the chosen one, else the CLI's default).
    @Binding var rule: VersionRule
    /// The Branch rule's branch name.
    @Binding var branch: String
    /// What each rule writes to skills.toml; nil shows none.
    let constraint: (VersionRule) -> String?
    /// The button's label instead of the rule's (`As in skills.toml` while an entry keeps its constraint).
    var keptLabel: String?
    /// The constraint shown with `keptLabel`.
    var keptConstraint: String?

    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover = true
        } label: {
            HStack(spacing: Spacing.inline) {
                Text(keptLabel ?? AddSkillCopy.ruleLabel(rule, base: base))
                if let text = keptLabel == nil ? constraint(rule) : keptConstraint {
                    Text(text)
                        .font(Font.Token.monoSmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityHint(AddSkillCopy.ruleHint)
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            popover
        }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Picker(AddSkillCopy.versionRule, selection: $rule) {
                ForEach(options, id: \.self) { option in
                    HStack(spacing: Spacing.inline) {
                        Text(AddSkillCopy.ruleLabel(option, base: base))
                        if case .branch = option {
                            EmptyView()
                        } else if let text = constraint(option) {
                            Text(text)
                                .font(Font.Token.monoSmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .tag(option)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if case .branch = rule {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    TextField(AddSkillCopy.branchLabel, text: $branch, prompt: Text(AddSkillCopy.branchLabel))
                        .textFieldStyle(.roundedBorder)
                        .font(Font.Token.mono)
                        .frame(width: Self.branchWidth)
                    if !branch.isEmpty, !VersionRule.isValidBranch(branch) {
                        Text(AddSkillCopy.branchProblem)
                            .font(Font.Token.caption)
                            .foregroundStyle(Color.statusErrorText)
                    }
                }
                .padding(.leading, Spacing.l)
            }
        }
        .font(Font.Token.body)
        .padding(Spacing.m)
    }

    /// The branch field's width: the rename field's 300 pt would outgrow the popover; a branch name is short.
    static let branchWidth: CGFloat = 200
}
