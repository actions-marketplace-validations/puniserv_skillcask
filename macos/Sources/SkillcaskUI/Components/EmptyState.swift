import SwiftUI

/// The empty-state block (Components board "Empty state", Overview-States, List-States, Contents-States): an
/// optional SF Symbol, a `type.headline` title, a secondary body, an optional mono detail line, a row of system
/// push buttons and an optional accent link with the text it discloses, centred in a column with `Spacing.s`
/// between them.
///
/// `.dashed` is the Overview's hint block: a 1 pt `Color.separatorStrong` dashed border inside `Radius.l` on
/// `Color.surfaceCard`, 28/20 padding, hugging its content. `.plain` is the in-column message of the list and the
/// Contents tab: no border, no fill, centred in all the space it is offered, `Spacing.xxl` padding. The body is
/// `type.body` in the dashed block (Overview) and `type.callout` in a column (List, Contents), as the boards draw
/// them; runs between backticks in the body are file names set in `type.mono.small` (see `EmptyCopy`).
///
/// Buttons are system controls: the primary one `.borderedProminent` tinted `Color.accent`, the others
/// `.bordered`, in the order given (the Overview puts the primary first, Contents puts it last). A shortcut hint
/// such as `⌘O` is text in the label only; the screen binds the real `.keyboardShortcut`.
public struct EmptyState: View {
    /// How the block sits on its column.
    public enum Style: Hashable, Sendable {
        /// The Overview hint block: dashed border on the card surface.
        case dashed
        /// The list and Contents message: no border, no fill.
        case plain
    }

    /// The symbol colour: tertiary text for an empty place, the error text colour for a file problem.
    public enum Tone: Hashable, Sendable {
        case quiet
        case error
    }

    /// One button or the link.
    public struct Action {
        public let title: String
        /// Text drawn after the title inside the button (`⌘O`), never a binding.
        public let shortcutHint: String?
        public let isPrimary: Bool
        public let perform: () -> Void

        /// The accent-tinted default button.
        public static func primary(
            _ title: String, shortcutHint: String? = nil, perform: @escaping () -> Void
        )
            -> Action
        {
            Action(title: title, shortcutHint: shortcutHint, isPrimary: true, perform: perform)
        }

        /// A bordered button, or the link when passed as `link`.
        public static func secondary(
            _ title: String, shortcutHint: String? = nil, perform: @escaping () -> Void
        )
            -> Action
        {
            Action(title: title, shortcutHint: shortcutHint, isPrimary: false, perform: perform)
        }

        /// The button label: `Open Folder… ⌘O`.
        public var label: String {
            guard let shortcutHint else { return title }
            return title + " " + shortcutHint
        }
    }

    public let icon: String?
    /// A small symbol drawn inside `icon`'s page, as the boards' file-problem glyph draws an X in a document.
    public let iconBadge: String?
    public let tone: Tone
    public let title: String
    /// The secondary sentence under the title (the board's body; `body` is the view's).
    public let message: String?
    /// A mono line under the body: the path of an unreadable file.
    public let detail: String?
    public let actions: [Action]
    public let link: Action?
    /// Text the link has disclosed, under it in `type.mono.small`; nil while closed.
    public let disclosed: String?
    public let style: Style
    /// The widest the body runs before it wraps; nil lets it take the block's width.
    public let textWidth: CGFloat?

    public init(
        icon: String?, iconBadge: String? = nil, tone: Tone = .quiet, title: String, body: String? = nil,
        detail: String? = nil, actions: [Action] = [], link: Action? = nil, disclosed: String? = nil,
        style: Style = .plain, textWidth: CGFloat? = nil
    ) {
        self.icon = icon
        self.iconBadge = iconBadge
        self.tone = tone
        self.title = title
        self.message = body
        self.detail = detail
        self.actions = actions
        self.link = link
        self.disclosed = disclosed
        self.style = style
        self.textWidth = textWidth
    }

    // MARK: - Board values

    /// The symbol size: every screen board draws a 32 pt glyph (the Components sheet's sample 28).
    static let iconSize: CGFloat = 32
    /// The SVG glyphs' `stroke-width: 1.2` on a 16-unit box at 32 pt reads as a light SF Symbol weight.
    static let iconWeight: Font.Weight = .light
    /// The badge inside the page: the Contents-States X spans 4 of the glyph's 16 units, centred 2 units below the
    /// page's middle.
    static let badgeSize: CGFloat = iconSize / 4
    static let badgeOffset: CGFloat = iconSize / 8
    /// The dashed block's vertical padding (`padding: 28px 20px`, Overview-States).
    static let dashedPaddingV: CGFloat = 28
    /// CSS `border: 1px dashed`: 3 pt dashes, 3 pt gaps, the closest a stroke gets to a 1 px dashed border.
    nonisolated static let dash: [CGFloat] = [3, 3]
    /// Overview-States "No projects yet": body `max-width: 360px`.
    public static let noProjectsTextWidth: CGFloat = 360
    /// Overview-States "Folder without skills.toml": body `max-width: 380px`.
    public static let notSetUpTextWidth: CGFloat = 380
    /// Contents-States "Too large": body `max-width: 280px`.
    public static let tooLargeTextWidth: CGFloat = 280
    /// Contents-States "Unreadable": body `max-width: 290px`.
    public static let unreadableTextWidth: CGFloat = 290

    /// The P2-11 rule: a dashed hairline for `.dashed`, no border for `.plain`.
    nonisolated public static func border(for style: Style) -> StrokeStyle? {
        switch style {
        case .dashed: StrokeStyle(lineWidth: Size.hairline, dash: dash)
        case .plain: nil
        }
    }

    /// The fill under the block: the card surface for `.dashed`, none for `.plain`.
    nonisolated public static func fill(for style: Style) -> Color? {
        style == .dashed ? Color.surfaceCard : nil
    }

    // MARK: - Body

    public var body: some View {
        switch style {
        case .dashed:
            content
                .padding(.vertical, Self.dashedPaddingV)
                .padding(.horizontal, Spacing.xl)
                .frame(maxWidth: .infinity)
                .background(Self.fill(for: style) ?? .clear, in: shape)
                .overlay(dashedBorder)
        case .plain:
            content
                .padding(Spacing.xxl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Subviews

    private var content: some View {
        VStack(spacing: Spacing.s) {
            if let icon {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(Self.iconWeight)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .overlay { iconBadge.map(badge) }
                    .foregroundStyle(tone == .error ? Color.statusErrorText : Color.textTertiary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(Font.Token.headline)
                .foregroundStyle(Color.textPrimary)
            if let message {
                Self.bodyText(message)
                    .font(style == .dashed ? Font.Token.body : Font.Token.callout)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: textWidth)
                    .accessibilityLabel(EmptyCopy.plain(message))
            }
            if let detail {
                Text(detail)
                    .font(Font.Token.monoSmall)
                    .foregroundStyle(Color.textSecondary)
                    .textSelection(.enabled)
            }
            if !actions.isEmpty {
                buttons.padding(.top, Spacing.xs)
            }
            if let link {
                Button(action: link.perform) {
                    Text(link.label)
                        .font(Font.Token.calloutMedium)
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.s)
            }
            if let disclosed {
                Text(disclosed)
                    .font(Font.Token.monoSmall)
                    .foregroundStyle(Color.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: textWidth)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.medium)
            .frame(width: Self.badgeSize, height: Self.badgeSize)
            .offset(y: Self.badgeOffset)
    }

    private var buttons: some View {
        HStack(spacing: Spacing.s) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                if action.isPrimary {
                    Button(action.label, action: action.perform)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accent)
                } else {
                    Button(action.label, action: action.perform)
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var dashedBorder: some View {
        shape.strokeBorder(Color.separatorStrong, style: Self.border(for: style) ?? StrokeStyle())
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.l)
    }

    /// The body with its backtick runs in `type.mono.small`; the marks themselves are not drawn.
    static func bodyText(_ body: String) -> Text {
        let parts = body.split(separator: "`", omittingEmptySubsequences: false)
        return parts.enumerated()
            .reduce(Text(verbatim: "")) { text, part in
                let run = Text(verbatim: String(part.element))
                return text + (part.offset.isMultiple(of: 2) ? run : run.font(Font.Token.monoSmall))
            }
    }
}

#Preview("EmptyState, light") {
    EmptyStateSample()
}

#Preview("EmptyState, dark") {
    EmptyStateSample()
        .preferredColorScheme(.dark)
}

/// The Overview hint block over the grouped ground, then the list's empty message.
private struct EmptyStateSample: View {
    /// About the detail column of the 1280 pt boards.
    static let width: CGFloat = 620

    var body: some View {
        VStack(spacing: Spacing.l) {
            EmptyState(
                icon: "folder.badge.plus", title: EmptyCopy.noProjectsTitle, body: EmptyCopy.noProjectsBody,
                actions: [
                    .primary(EmptyCopy.openFolder, shortcutHint: EmptyCopy.openFolderShortcut) {},
                    .secondary(EmptyCopy.findProjects) {},
                ],
                style: .dashed, textWidth: EmptyState.noProjectsTextWidth)
            EmptyState(
                icon: "shippingbox", title: EmptyCopy.noSkillsTitle, body: EmptyCopy.noSkillsBody,
                actions: [.primary(EmptyCopy.addSkill) {}])
        }
        .padding(Spacing.l)
        .frame(width: Self.width)
        .background(Color.surfaceWindow)
    }
}
