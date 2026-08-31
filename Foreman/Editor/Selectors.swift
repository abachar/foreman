import Foundation
import SwiftTreeSitter

/// editor R47, R48: what a stylesheet defines, and what an HTML attribute asks for.
///
/// Both read the tree-sitter trees the app already loads (`editor` R11) rather than scanning
/// text: `class="a b"` inside a string, a selector inside a comment and `.a` in a media query all
/// look the same to a regular expression and not at all the same to the grammar.
nonisolated enum Selectors {
    /// The nodes whose `class_name` child is a pseudo-class, not a class.
    static let pseudoSelectors: Set<String> = ["pseudo_class_selector", "pseudo_element_selector"]

    /// A class or an id — the two things a `cmd+click` can land on and a stylesheet can define.
    enum Kind: Equatable, Sendable {
        case classSelector
        case idSelector
    }

    /// One selector as a stylesheet defines it (editor R47).
    struct Definition: Equatable, Sendable {
        let name: String
        let kind: Kind
        /// 1-based, for `Editor.open(…, line:)`.
        let line: Int
    }

    /// One name as an HTML attribute asks for it (editor R48).
    struct Reference: Equatable, Sendable {
        let name: String
        let kind: Kind
    }

    /// editor R47: every class and id a stylesheet defines, with the line it is on.
    ///
    /// A compound selector registers each name it holds: `.card .title` defines both, and
    /// `a.btn:hover` defines `btn` — the tree gives them separately, so nothing has to be parsed.
    static func definitions(in css: String) -> [Definition] {
        let parser = Parser()
        guard (try? parser.setLanguage(Language.css.treeSitterLanguage)) != nil, let tree = parser.parse(css),
            let root = tree.rootNode
        else { return [] }
        let text = css as NSString
        var found: [Definition] = []
        visit(root) { node in
            guard let type = node.nodeType else { return }
            let kind: Kind
            switch type {
            case "class_name": kind = .classSelector
            case "id_name": kind = .idSelector
            default: return
            }
            // The grammar calls a pseudo-class's name a `class_name` too, so `:hover` would be
            // indexed as a class and `class="hover"` would jump to it (found 2026-08-31, 18.5).
            guard !Self.pseudoSelectors.contains(node.parent?.nodeType ?? "") else { return }
            let range = node.range
            guard range.location >= 0, NSMaxRange(range) <= text.length else { return }
            found.append(
                Definition(
                    name: text.substring(with: range), kind: kind,
                    line: Int(node.pointRange.lowerBound.row) + 1))
        }
        return found
    }

    /// editor R48: the class or id under `location` in an HTML file, or `nil`.
    ///
    /// The word under the pointer, not the first of the list: `class="btn btn-primary"` has two
    /// names and a click means the one it landed on.
    static func reference(at location: Int, in html: String) -> Reference? {
        let parser = Parser()
        guard (try? parser.setLanguage(Language.html.treeSitterLanguage)) != nil, let tree = parser.parse(html),
            let root = tree.rootNode
        else { return nil }
        let text = html as NSString
        var attribute: Node?
        visit(root) { node in
            guard node.nodeType == "attribute", NSLocationInRange(location, node.range) else { return }
            attribute = node
        }
        guard let attribute, let kind = kind(ofAttribute: attribute, in: text),
            let value = valueRange(of: attribute, in: text), NSLocationInRange(location, value)
        else { return nil }
        let name = word(at: location, in: text, within: value)
        return name.isEmpty ? nil : Reference(name: name, kind: kind)
    }

    /// `class` and `id` are the only two attributes that name a selector.
    private static func kind(ofAttribute attribute: Node, in text: NSString) -> Kind? {
        var kind: Kind?
        attribute.enumerateChildren { child in
            guard child.nodeType == "attribute_name", NSMaxRange(child.range) <= text.length else { return }
            switch text.substring(with: child.range).lowercased() {
            case "class": kind = .classSelector
            case "id": kind = .idSelector
            default: kind = nil
            }
        }
        return kind
    }

    /// The characters of the attribute's value, quotes excluded.
    private static func valueRange(of attribute: Node, in text: NSString) -> NSRange? {
        var range: NSRange?
        attribute.enumerateChildren { child in
            switch child.nodeType {
            case "attribute_value":
                range = child.range
            case "quoted_attribute_value":
                child.enumerateChildren { inner in
                    if inner.nodeType == "attribute_value" {
                        range = inner.range
                    }
                }
            default:
                break
            }
        }
        guard let range, NSMaxRange(range) <= text.length else { return nil }
        return range
    }

    /// The whitespace-delimited word containing `location`, clipped to `bounds`.
    static func word(at location: Int, in text: NSString, within bounds: NSRange) -> String {
        var start = min(max(location, bounds.location), NSMaxRange(bounds))
        var end = start
        while start > bounds.location, !isSeparator(text.character(at: start - 1)) {
            start -= 1
        }
        while end < NSMaxRange(bounds), !isSeparator(text.character(at: end)) {
            end += 1
        }
        return text.substring(with: NSRange(location: start, length: end - start))
    }

    private static func isSeparator(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }

    /// Pre-order on an explicit stack, as `Folding` walks: deep trees must not overflow.
    private static func visit(_ node: Node, _ body: (Node) -> Void) {
        var stack = [node]
        while let current = stack.popLast() {
            body(current)
            var children: [Node] = []
            current.enumerateChildren { children.append($0) }
            stack.append(contentsOf: children.reversed())
        }
    }
}
