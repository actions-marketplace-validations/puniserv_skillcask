import SwiftUI

/// The two line-number columns of a diff row (Components board `.dl` grid `36px 36px`): the old number on the
/// left, the new on the right, each right-aligned in `monoSmall` and `textTertiary` with the board's 8 pt inner
/// padding; a hunk header or note leaves both empty. Drawn by hand: the one custom piece of the review sheet.
public struct DiffGutter: View {
    /// One number column, from the board's `grid-template-columns: 36px 36px`.
    nonisolated public static let columnWidth: CGFloat = 36
    /// Both columns: what the text column of every row starts after.
    nonisolated public static var width: CGFloat { 2 * columnWidth }

    public let oldNumber: Int?
    public let newNumber: Int?

    public init(oldNumber: Int?, newNumber: Int?) {
        self.oldNumber = oldNumber
        self.newNumber = newNumber
    }

    public var body: some View {
        HStack(spacing: 0) {
            column(oldNumber)
            column(newNumber)
        }
        .frame(width: Self.width, height: Font.Token.LineHeight.diff, alignment: .top)
        .accessibilityHidden(true)
    }

    // MARK: - Subviews

    /// `textTertiary` at 11 pt follows the board's `.g{color:var(--text3)}` although the type rule keeps 11 pt
    /// text at `textSecondary` or darker: line numbers are navigation chrome, not something to read, and the
    /// board draws them that way on purpose.
    private func column(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(Font.Token.monoSmall)
            .foregroundStyle(Color.textTertiary)
            .lineLimit(1)
            .padding(.trailing, Spacing.s)
            .frame(width: Self.columnWidth, height: Font.Token.LineHeight.diff, alignment: .trailing)
    }
}

#Preview("DiffGutter, light") {
    VStack(spacing: 0) {
        DiffGutter(oldNumber: 10, newNumber: 10)
        DiffGutter(oldNumber: 11, newNumber: nil)
        DiffGutter(oldNumber: nil, newNumber: 11)
        DiffGutter(oldNumber: nil, newNumber: nil)
        DiffGutter(oldNumber: 1234, newNumber: 1240)
    }
    .padding(Spacing.l)
    .background(Color.surfaceWindow)
}

#Preview("DiffGutter, dark") {
    VStack(spacing: 0) {
        DiffGutter(oldNumber: 10, newNumber: 10)
        DiffGutter(oldNumber: 11, newNumber: nil)
        DiffGutter(oldNumber: nil, newNumber: 11)
        DiffGutter(oldNumber: nil, newNumber: nil)
        DiffGutter(oldNumber: 1234, newNumber: 1240)
    }
    .padding(Spacing.l)
    .background(Color.surfaceWindow)
    .preferredColorScheme(.dark)
}
