import SkillcaskCore
import SwiftUI

/// The Add run inside the sheet (S11, AddSkill-States "Progress — live lines, Cancel"): the system spinner, the
/// run's title and the time since it started, the CLI's lines as they arrive in a mono box kept scrolled to the
/// newest, and Hide output. The sheet's footer holds Cancel.
struct AddSkillProgress: View {
    /// What the block draws: the runner's live action, or a fixed sample in previews.
    struct Model: Sendable {
        let title: String
        let startedAt: Date
        let lines: [OutputLine]

        init(title: String, startedAt: Date, lines: [OutputLine]) {
            self.title = title
            self.startedAt = startedAt
            self.lines = lines
        }

        init(_ action: ActionRunner.RunningAction) {
            self.init(title: action.title, startedAt: action.startedAt, lines: action.lines)
        }
    }

    let model: Model

    @State private var showsOutput = true

    /// The output box: `height: 112px` on the board (seven 16 pt lines).
    static let outputHeight: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            HStack(spacing: Spacing.cardGap) {
                ProgressView()
                    .controlSize(.small)
                Text(model.title)
                    .font(Font.Token.bodyEmphasis)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Spacing.s)
                TimelineView(.periodic(from: model.startedAt, by: 1)) { context in
                    Text(AddSkillCopy.elapsed(Int(context.date.timeIntervalSince(model.startedAt))))
                        .font(Font.Token.caption)
                        .foregroundStyle(Color.textSecondary)
                        .monospacedDigit()
                }
            }
            if showsOutput {
                output
            }
            Button {
                showsOutput.toggle()
            } label: {
                Text(showsOutput ? AddSkillCopy.hideOutput : AddSkillCopy.showOutput)
                    .font(Font.Token.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Size.cardPaddingH)
        .padding(.horizontal, Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.title)
    }

    private var output: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in
                    Text(Self.text(of: line))
                        .font(Font.Token.monoSmall)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
            .padding(.vertical, Spacing.s)
            .padding(.horizontal, Spacing.cardGap)
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: Self.outputHeight)
        .background(Color.surfaceGrouped, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }

    static func text(of line: OutputLine) -> String {
        switch line {
        case .stdout(let text), .stderr(let text): text
        }
    }
}
