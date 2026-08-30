import Foundation
import Markdown

/// The preview's model (editor R14): swift-markdown's AST reduced to what the view draws.
///
/// Built off the main actor; `AttributedString` carries the inline styles and links.
nonisolated indirect enum MarkdownBlock: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let checked: Bool?
        let blocks: [MarkdownBlock]
    }

    case heading(level: Int, AttributedString)
    case paragraph(AttributedString)
    case code(language: String?, String)
    case list(ordered: Bool, start: Int, [Item])
    case quote([MarkdownBlock])
    case rule
    case table(header: [AttributedString], rows: [[AttributedString]])
    case image(URL, alt: String)
    case html(String)
}

nonisolated enum MarkdownBlocks {
    /// design R6 (2026-08-30): the bullet of a list at `depth`, GitHub's disc → circle → square,
    /// cycling beyond the third level as CSS does.
    static func bullet(depth: Int) -> String {
        ["\u{25CF}", "\u{25CB}", "\u{25AA}"][max(depth, 0) % 3]
    }

    /// design R6 (2026-08-30): the number of an ordered item at `depth`, GitHub's decimal →
    /// lower-roman → lower-alpha, cycling beyond the third level.
    static func number(_ value: Int, depth: Int) -> String {
        switch max(depth, 0) % 3 {
        case 1:
            return roman(value)
        case 2:
            return alpha(value)
        default:
            return String(value)
        }
    }

    /// A lower-case Roman numeral: `1 → i`, `4 → iv`, `2026 → mmxxvi`.
    ///
    /// Outside what Roman numerals can write, the decimal is kept.
    static func roman(_ value: Int) -> String {
        guard value > 0, value < 4000 else { return String(value) }
        let numerals: [(Int, String)] = [
            (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"), (50, "l"), (40, "xl"),
            (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
        ]
        var rest = value
        var result = ""
        for (amount, numeral) in numerals {
            while rest >= amount {
                result += numeral
                rest -= amount
            }
        }
        return result
    }

    /// `1 → a`, `26 → z`, `27 → aa`, as CSS `lower-alpha` counts.
    static func alpha(_ value: Int) -> String {
        guard value > 0 else { return String(value) }
        var rest = value
        var result = ""
        while rest > 0 {
            let index = (rest - 1) % 26
            result = String(UnicodeScalar(UInt8(97 + index))) + result
            rest = (rest - 1) / 26
        }
        return result
    }

    /// Parses `text` for the file at `file` (links and images resolve relative to it).
    @concurrent
    static func make(_ text: String, file: URL, root: URL) async -> [MarkdownBlock] {
        let context = Context(file: file, root: root)
        return blocks(of: Document(parsing: text), context)
    }

    private struct Context {
        let file: URL
        let root: URL
    }

    private static func blocks(of container: some Markup, _ context: Context) -> [MarkdownBlock] {
        container.children.compactMap { block(of: $0, context) }
    }

    private static func block(of markup: Markup, _ context: Context) -> MarkdownBlock? {
        switch markup {
        case let heading as Heading:
            return .heading(level: heading.level, inline(of: heading, context))
        case let paragraph as Paragraph:
            if paragraph.childCount == 1, let image = paragraph.child(at: 0) as? Image,
                let url = MarkdownLinks.image(image.source ?? "", from: context.file, root: context.root)
            {
                return .image(url, alt: image.plainText)
            }
            return .paragraph(inline(of: paragraph, context))
        case let code as CodeBlock:
            return .code(language: code.language, code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code)
        case let list as UnorderedList:
            return .list(ordered: false, start: 1, items(of: list, context))
        case let list as OrderedList:
            return .list(ordered: true, start: Int(list.startIndex), items(of: list, context))
        case let quote as BlockQuote:
            return .quote(blocks(of: quote, context))
        case is ThematicBreak:
            return .rule
        case let table as Table:
            let header = Array(table.head.cells.map { inline(of: $0, context) })
            let rows = Array(table.body.rows.map { row in Array(row.cells.map { inline(of: $0, context) }) })
            return .table(header: header, rows: rows)
        case let html as HTMLBlock:
            return .html(html.rawHTML)
        default:
            return nil
        }
    }

    private static func items(of list: some ListItemContainer, _ context: Context) -> [MarkdownBlock.Item] {
        list.listItems.map { item in
            let checked: Bool?
            switch item.checkbox {
            case .checked:
                checked = true
            case .unchecked:
                checked = false
            case nil:
                checked = nil
            }
            return MarkdownBlock.Item(checked: checked, blocks: blocks(of: item, context))
        }
    }

    /// Inline content as one attributed string: emphasis, strong, code, strikethrough, links.
    private static func inline(of container: some Markup, _ context: Context) -> AttributedString {
        var result = AttributedString()
        for child in container.children {
            result.append(inlineNode(child, context))
        }
        return result
    }

    private static func inlineNode(_ markup: Markup, _ context: Context) -> AttributedString {
        switch markup {
        case let text as Markdown.Text:
            return AttributedString(text.string)
        case is SoftBreak:
            return AttributedString(" ")
        case is LineBreak:
            return AttributedString("\n")
        case let code as InlineCode:
            var string = AttributedString(code.code)
            string.inlinePresentationIntent = .code
            return string
        case let emphasis as Emphasis:
            var string = inline(of: emphasis, context)
            string.inlinePresentationIntent = .emphasized
            return string
        case let strong as Strong:
            var string = inline(of: strong, context)
            string.inlinePresentationIntent = .stronglyEmphasized
            return string
        case let strike as Strikethrough:
            var string = inline(of: strike, context)
            string.inlinePresentationIntent = .strikethrough
            return string
        case let link as Link:
            var string = inline(of: link, context)
            switch MarkdownLinks.resolve(link.destination ?? "", from: context.file, root: context.root) {
            case .file(let url), .external(let url):
                string.link = url
            case .ignored:
                break
            }
            return string
        case let image as Image:
            return AttributedString(image.plainText.isEmpty ? "[image]" : "[\(image.plainText)]")
        case let html as InlineHTML:
            return AttributedString(html.rawHTML)
        default:
            return AttributedString(markup.format())
        }
    }
}
