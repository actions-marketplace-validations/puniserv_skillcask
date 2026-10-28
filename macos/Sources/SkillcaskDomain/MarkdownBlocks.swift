/// The block structure of a SKILL.md body, for the Contents tab's read-only rendering (ADR §9 risk 5): headings,
/// paragraphs, bullet and numbered lists, fenced code blocks, block quotes and horizontal rules. Everything inside a
/// block (emphasis, inline code, links) stays as Markdown source for the view's inline renderer; a fenced code
/// block keeps its lines verbatim. Not CommonMark: no setext headings, no indented code blocks, no lazy
/// continuation of quotes, no HTML blocks; tables read as paragraphs. Pure, so the tests pin every rule.
public enum MarkdownBlocks {
    /// One block of the body.
    public enum Block: Hashable, Sendable {
        /// `# Title` … `###### Title`: the level and the text without the marks.
        case heading(level: Int, text: String)
        /// Consecutive non-blank lines, joined by newlines (the view keeps the line breaks).
        case paragraph(String)
        /// `- a`, `* a`, `+ a` (`ordered == false`) or `1. a`, `1) a`; `start` is the first item's number.
        case list(ordered: Bool, start: Int, items: [Item])
        /// A ``` or ~~~ fence: the info string's first word and the lines in between, unchanged.
        case code(language: String?, text: String)
        /// `> text` lines, the marks removed, joined by newlines.
        case quote(String)
        /// `---`, `***`, `___` (three or more, spaces allowed).
        case rule
    }

    /// One list item: its text (continuation lines joined by newlines) and how deeply it is nested.
    public struct Item: Hashable, Sendable {
        public let text: String
        /// 0 for a top-level item; one more for every two columns of indentation.
        public let depth: Int

        public init(text: String, depth: Int = 0) {
            self.text = text
            self.depth = depth
        }
    }

    /// A block and the body lines it came from (0-based, fences and markers included, blank lines between
    /// blocks excluded), so a file line from the audit can be found in the rendered body.
    public struct Span: Hashable, Sendable {
        public let block: Block
        public let lines: ClosedRange<Int>

        public init(block: Block, lines: ClosedRange<Int>) {
            self.block = block
            self.lines = lines
        }
    }

    /// Splits `body` into blocks, in order.
    public static func parse(_ body: String) -> [Block] {
        spans(body).map(\.block)
    }

    /// Splits `body` into blocks with their line ranges, in order.
    public static func spans(_ body: String) -> [Span] {
        var parser = Parser()
        for (index, line) in body.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            parser.line = index
            parser.feed(String(line))
        }
        parser.finish()
        return parser.spans
    }

    /// The index of the span holding body line `line` (0-based); nil for a blank line between blocks.
    public static func span(containing line: Int, in spans: [Span]) -> Int? {
        spans.firstIndex { $0.lines.contains(line) }
    }

    // MARK: - Line shapes

    /// The fence a line opens or closes: its character, its length and the info string after it.
    static func fence(_ line: String) -> (mark: Character, count: Int, info: String)? {
        let trimmed = leadingTrimmed(line, max: 3)
        guard let mark = trimmed.first, mark == "`" || mark == "~" else { return nil }
        let count = trimmed.prefix { $0 == mark }.count
        guard count >= 3 else { return nil }
        let info = trimmed.dropFirst(count).trimmingSpaces()
        // A backtick fence's info string may not contain a backtick (CommonMark), else it is inline code.
        if mark == "`", info.contains("`") {
            return nil
        }
        return (mark, count, info)
    }

    static func heading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = leadingTrimmed(line, max: 3)
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingSpaces()
        // A closing sequence of #s preceded by a space is not part of the text.
        let closing = text.reversed().prefix { $0 == "#" }.count
        if closing > 0 {
            let kept = text.dropLast(closing)
            if kept.isEmpty || kept.last == " " {
                text = kept.trimmingSpaces()
            }
        }
        return (level, text)
    }

    static func isRule(_ line: String) -> Bool {
        let marks = leadingTrimmed(line, max: 3).filter { $0 != " " && $0 != "\t" }
        guard let mark = marks.first, mark == "-" || mark == "*" || mark == "_" else { return false }
        return marks.count >= 3 && marks.allSatisfy { $0 == mark }
    }

    /// A list marker: ordered or not, the number, the text after the marker and the indentation before it.
    static func listItem(_ line: String) -> (ordered: Bool, number: Int, text: String, indent: Int)? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        if let mark = trimmed.first, mark == "-" || mark == "*" || mark == "+" {
            let rest = trimmed.dropFirst()
            guard rest.first == " " || rest.first == "\t" else { return nil }
            return (false, 1, rest.trimmingSpaces(), indent)
        }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard (1...9).contains(digits.count), let number = Int(digits) else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")" else { return nil }
        let rest = afterDigits.dropFirst()
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return (true, number, rest.trimmingSpaces(), indent)
    }

    static func quoteLine(_ line: String) -> String? {
        let trimmed = leadingTrimmed(line, max: 3)
        guard trimmed.first == ">" else { return nil }
        var rest = trimmed.dropFirst()
        if rest.first == " " {
            rest = rest.dropFirst()
        }
        return String(rest)
    }

    private static func leadingTrimmed(_ line: String, max: Int) -> Substring {
        let spaces = line.prefix { $0 == " " }.count
        return spaces <= max ? line.dropFirst(spaces) : Substring(line)
    }

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    // MARK: - Parser

    /// A line-at-a-time state machine: one open block at most.
    private struct Parser {
        enum Open {
            case paragraph([String])
            case list(ordered: Bool, start: Int, items: [Item])
            case code(mark: Character, count: Int, language: String?, lines: [String])
            case quote([String])
        }

        var spans: [Span] = []
        var open: Open?
        /// The body line being fed.
        var line = 0
        /// The first and the last line of the open block.
        var openStart = 0
        var openEnd = 0

        /// A block of one line, closed at once.
        mutating func emit(_ block: Block) {
            spans.append(Span(block: block, lines: line...line))
        }

        /// Opens a block at the current line.
        mutating func start(_ block: Open) {
            open = block
            openStart = line
            openEnd = line
        }

        /// The open block takes the current line.
        mutating func extend(_ block: Open) {
            open = block
            openEnd = line
        }

        mutating func feed(_ line: String) {
            if case .code(let mark, let count, let language, var lines) = open {
                if let closing = fence(line), closing.mark == mark, closing.count >= count, closing.info.isEmpty {
                    openEnd = self.line
                    finish()
                } else {
                    lines.append(line)
                    extend(.code(mark: mark, count: count, language: language, lines: lines))
                }
                return
            }
            if isBlank(line) {
                finish()
                return
            }
            if let opening = fence(line) {
                finish()
                let language = opening.info.split(separator: " ").first.map(String.init)
                start(.code(mark: opening.mark, count: opening.count, language: language, lines: []))
                return
            }
            if let heading = heading(line) {
                finish()
                emit(.heading(level: heading.level, text: heading.text))
                return
            }
            if isRule(line) {
                finish()
                emit(.rule)
                return
            }
            if let item = listItem(line) {
                addItem(item)
                return
            }
            if let quoted = quoteLine(line) {
                if case .quote(var lines) = open {
                    lines.append(quoted)
                    extend(.quote(lines))
                } else {
                    finish()
                    start(.quote([quoted]))
                }
                return
            }
            continueText(line)
        }

        /// Closes the open block; an unclosed fence runs to the end of the body.
        mutating func finish() {
            let block: Block
            switch open {
            case nil: return
            case .paragraph(let lines): block = .paragraph(lines.joined(separator: "\n"))
            case .list(let ordered, let start, let items): block = .list(ordered: ordered, start: start, items: items)
            case .code(_, _, let language, let lines):
                block = .code(language: language, text: lines.joined(separator: "\n"))
            case .quote(let lines): block = .quote(lines.joined(separator: "\n"))
            }
            spans.append(Span(block: block, lines: openStart...openEnd))
            open = nil
        }

        /// A new item joins the open list when it is nested or of the same kind; else a new list starts.
        private mutating func addItem(_ item: (ordered: Bool, number: Int, text: String, indent: Int)) {
            let depth = item.indent / 2
            if case .list(let ordered, let first, var items) = open, depth > 0 || ordered == item.ordered {
                items.append(Item(text: item.text, depth: depth))
                extend(.list(ordered: ordered, start: first, items: items))
                return
            }
            finish()
            start(.list(ordered: item.ordered, start: item.number, items: [Item(text: item.text, depth: 0)]))
        }

        /// A plain line continues the open paragraph, list item or quote, or starts a paragraph.
        private mutating func continueText(_ line: String) {
            let text = line.trimmingSpaces()
            switch open {
            case .paragraph(var lines):
                lines.append(text)
                extend(.paragraph(lines))
            case .list(let ordered, let first, var items):
                if let last = items.popLast() {
                    items.append(Item(text: last.text + "\n" + text, depth: last.depth))
                }
                extend(.list(ordered: ordered, start: first, items: items))
            case .quote(var lines):
                lines.append(text)
                extend(.quote(lines))
            case nil, .code:
                finish()
                start(.paragraph([text]))
            }
        }
    }
}

extension StringProtocol {
    /// Without leading and trailing spaces and tabs (no Foundation in Domain).
    fileprivate func trimmingSpaces() -> String {
        let isSpace: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        guard let first = firstIndex(where: { !isSpace($0) }), let last = lastIndex(where: { !isSpace($0) }) else {
            return ""
        }
        return String(self[first...last])
    }
}
