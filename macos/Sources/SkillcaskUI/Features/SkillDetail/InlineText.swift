import AppKit
import SwiftUI

/// A read-only, selectable block of `MarkdownInline` text laid out by TextKit 1 in a non-editable `NSTextView`,
/// for what SwiftUI's `Text` cannot draw on macOS 14: a line box of a fixed pitch with the baseline centred in it
/// as CSS does (`line-height: 20px`), and padded rounded fills behind `code` and escape runs. The whole block
/// selects and copies as one text, as a `Text` with `.textSelection(.enabled)` did.
///
/// Sizes itself through `sizeThatFits`: the proposed width, and the height the layout needs at that width, measured
/// in scratch TextKit objects so a probe width never reaches the live container (which tracks the view's width).
///
/// A heading block reports itself as a heading to accessibility (`InlineTextView.isHeading`); Esc passes up the
/// responder chain even while the text view is first responder, so the detail's `onExitCommand` still fires.
struct InlineText: NSViewRepresentable {
    let text: NSAttributedString
    let style: MarkdownInline.Style
    let isHeading: Bool

    init(_ text: NSAttributedString, style: MarkdownInline.Style, isHeading: Bool = false) {
        self.text = text
        self.style = style
        self.isHeading = isHeading
    }

    func makeNSView(context: Context) -> InlineTextView {
        let view = Self.makeTextView()
        update(view)
        return view
    }

    func updateNSView(_ view: InlineTextView, context: Context) {
        update(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: InlineTextView, context: Context) -> CGSize? {
        Self.fittingSize(text, style: style, width: proposal.width)
    }

    /// The live view: a non-editable, selectable text view over a `ChipLayoutManager` whose container follows the
    /// view's width.
    static func makeTextView() -> InlineTextView {
        let (storage, _, container) = stack(width: 0)
        container.widthTracksTextView = true
        let view = InlineTextView(frame: .zero, textContainer: container)
        view.storage = storage
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    /// The size `text` needs: the proposed width (a finite one, at least 1 pt) and the laid-out height there, or the
    /// unwrapped width when none is proposed. Lays out in its own storage, layout manager and container.
    static func fittingSize(_ text: NSAttributedString, style: MarkdownInline.Style, width: CGFloat?) -> CGSize {
        let width = width.flatMap { $0.isFinite ? max($0, 1) : nil }
        let (storage, layout, container) = stack(width: width ?? .greatestFiniteMagnitude)
        layout.lineHeight = style.lineHeight
        layout.baseFont = style.font
        storage.setAttributedString(text)
        let used = withExtendedLifetime(storage) {
            layout.ensureLayout(for: container)
            return layout.usedRect(for: container)
        }
        return CGSize(width: width ?? used.width.rounded(.up), height: used.height.rounded(.up))
    }

    /// One TextKit 1 stack: storage → `ChipLayoutManager` → a container `width` wide with no line padding. The
    /// storage owns the layout manager, which owns the container, so the caller keeps the storage alive.
    private static func stack(width: CGFloat) -> (NSTextStorage, ChipLayoutManager, NSTextContainer) {
        let storage = NSTextStorage()
        let layout = ChipLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        return (storage, layout, container)
    }

    private func update(_ view: InlineTextView) {
        view.isHeading = isHeading
        guard let layout = view.layoutManager as? ChipLayoutManager, let storage = view.textStorage else { return }
        layout.lineHeight = style.lineHeight
        layout.baseFont = style.font
        if !storage.isEqual(to: text) {
            storage.setAttributedString(text)
        }
    }
}

/// The text view of an `InlineText`.
final class InlineTextView: NSTextView {
    /// `AXHeading`, the value of AppKit's `NSAccessibility.Role.headingRole` (macOS 26) and the role WebKit has always
    /// given headings, spelled out so macOS 14 and 15 get it too.
    static let headingRole = NSAccessibility.Role(rawValue: "AXHeading")

    /// A Markdown heading block: accessibility sees a heading rather than a text area.
    var isHeading = false
    /// The top of the view's TextKit stack (storage → layout manager → container), kept alive here: a text view
    /// made with `init(frame:textContainer:)` does not own it.
    fileprivate var storage: NSTextStorage?

    /// `AXHeading` for a heading block; the text view's own `AXTextArea` for body text.
    override func accessibilityRole() -> NSAccessibility.Role? {
        isHeading ? Self.headingRole : super.accessibilityRole()
    }

    /// Esc: a text view would keep it (`complete:`); the next responder gets it instead, up to the hosting view, so
    /// SwiftUI's `onExitCommand` around the block still runs.
    override func cancelOperation(_ sender: Any?) {
        nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender)
    }
}

/// Fixes every line fragment to `lineHeight` with the baseline where CSS puts it (half the leading above the base
/// font's ascender), and draws the `MarkdownInline.Chip` fills behind the glyphs, under the selection.
final class ChipLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// Set from the block's `MarkdownInline.Style` before every layout.
    var lineHeight: CGFloat = 0
    var baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    /// The distance from a line's top to its baseline: `(lineHeight − (ascender + descender)) / 2 + ascender`.
    static func baseline(lineHeight: CGFloat, font: NSFont) -> CGFloat {
        let content = font.ascender - font.descender
        return (lineHeight - content) / 2 + font.ascender
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange
    ) -> Bool {
        lineFragmentRect.pointee.size.height = lineHeight
        lineFragmentUsedRect.pointee.size.height = lineHeight
        baselineOffset.pointee = Self.baseline(lineHeight: lineHeight, font: baseFont)
        return true
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage, let container = textContainers.first {
            let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            for chip in MarkdownInline.Chip.allCases {
                storage.enumerateAttribute(chip.key, in: characters) { value, range, _ in
                    guard value != nil else { return }
                    let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? baseFont
                    NSColor(chip.fill).setFill()
                    for rect in chipRects(range, chip: chip, font: font, in: container) {
                        let shifted = rect.offsetBy(dx: origin.x, dy: origin.y)
                        NSBezierPath(roundedRect: shifted, xRadius: chip.radius, yRadius: chip.radius).fill()
                    }
                }
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    /// One rect per line the run lies on: from the padding before its first glyph to the end of its last (whose
    /// kerning is the padding after), from the font's ascender to its descender around the baseline plus the
    /// vertical padding.
    private func chipRects(
        _ characters: NSRange, chip: MarkdownInline.Chip, font: NSFont, in container: NSTextContainer
    ) -> [NSRect] {
        let glyphs = glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        var rects: [NSRect] = []
        enumerateLineFragments(forGlyphRange: glyphs) { line, _, _, lineGlyphs, _ in
            let part = NSIntersectionRange(glyphs, lineGlyphs)
            guard part.length > 0 else { return }
            let bounds = self.boundingRect(forGlyphRange: part, in: container)
            let baseline = line.minY + self.location(forGlyphAt: part.location).y
            let top = baseline - font.ascender - chip.paddingV
            let bottom = baseline - font.descender + chip.paddingV
            rects.append(
                NSRect(
                    x: bounds.minX - chip.paddingH, y: top, width: bounds.width + chip.paddingH,
                    height: bottom - top))
        }
        return rects
    }
}
