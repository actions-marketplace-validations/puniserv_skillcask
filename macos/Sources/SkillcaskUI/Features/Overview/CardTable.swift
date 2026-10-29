import SkillcaskDomain
import SwiftUI

/// The small table of the Sources, Policy and Agents cards (Overview board `table`): 12 pt cells, headers in
/// medium `textSecondary`, a `separator` hairline above every row but the first, `5px 0` cell padding. Words wrap
/// in a narrow card (`Minimum release age`, `config.toml · enforced`), names in mono keep their width and a
/// secondary mono address wraps only after a
/// `/`; nothing truncates or breaks inside a word.
struct CardTable: View {
    /// One cell, typed so the table never carries a colour or font of its own.
    enum Cell: Hashable {
        case text(String)
        case medium(String)
        case mono(String)
        case monoSecondary(String)
        /// A secondary mono address that wraps only after a `/` (`OverviewCopy.addressRuns`), never inside a run.
        case address(String)
        case status(String, Severity)
        /// `config.toml · enforced`: the file in mono, the note in the warning text colour (Overview board).
        case enforced(String)
    }

    let headers: [String]
    let rows: [[Cell]]

    /// The board's `padding: 5px 0`; off the scale, so named.
    static let cellPadding: CGFloat = 5

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: Spacing.s, verticalSpacing: 0) {
            GridRow {
                ForEach(headers, id: \.self) { header in
                    Text(header)
                        .font(Font.Token.calloutMedium)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.bottom, Self.cellPadding)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Divider().overlay(Color.separator)
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        view(for: cell)
                            .padding(.vertical, Self.cellPadding)
                    }
                }
            }
        }
    }

    @ViewBuilder private func view(for cell: Cell) -> some View {
        switch cell {
        case .text(let text):
            Text(text).font(Font.Token.callout).foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        case .medium(let text):
            Text(text).font(Font.Token.calloutMedium).foregroundStyle(Color.textPrimary)
        case .mono(let text):
            Text(text).font(Font.Token.monoSmall).foregroundStyle(Color.textPrimary).fixedSize()
        case .monoSecondary(let text):
            Text(text).font(Font.Token.monoSmall).foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .address(let address):
            // A bare host (`packagist.org`) is one unbroken run: the table's Grid measures a flow at its narrowest
            // and would reserve a second line the host never uses. An address with a path wraps by runs.
            if address.contains("/") {
                FlowLayout(spacing: 0) {
                    ForEach(Array(OverviewCopy.addressRuns(address).enumerated()), id: \.offset) { _, run in
                        Text(run).font(Font.Token.monoSmall).foregroundStyle(Color.textSecondary).fixedSize()
                    }
                }
            } else {
                Text(address).font(Font.Token.monoSmall).foregroundStyle(Color.textSecondary).fixedSize()
            }
        case .status(let text, let severity):
            Text(text).font(Font.Token.calloutMedium).foregroundStyle(Color.statusText(severity))
        case .enforced(let origin):
            (Text(origin).font(Font.Token.monoSmall) + Text(CardCopy.separator)
                + Text(OverviewCopy.enforced).foregroundStyle(Color.statusText(.warning)))
                .font(Font.Token.callout)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
