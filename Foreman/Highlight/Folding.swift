import Foundation
import SwiftTreeSitter

/// editor R26: a foldable region, 1-based lines; folding keeps `first` and hides `first + 1 ... last`.
nonisolated struct FoldRegion: Equatable, Hashable, Sendable {
    let first: Int
    let last: Int

    func contains(line: Int) -> Bool {
        first <= line && line <= last
    }
}

/// editor R26: the regions of a text from its syntax tree — a second parse, Neon keeps its own
/// tree private (decision 2026-08-28).
nonisolated enum Folding {
    /// The tokens that open a block, an object or an argument list.
    static let openers: Set<String> = ["{", "[", "("]

    /// The closer of each opener, for the bracket pairs (editor R55).
    static let closers: [String: String] = ["{": "}", "[": "]", "(": ")"]

    /// editor R26, R13: the regions, `[]` when the grammar cannot parse.
    static func regions(in text: String, language: Language) -> [FoldRegion] {
        structure(in: text, language: language).regions
    }

    /// editor R26, R55 (2026-10-16): the fold regions and the bracket pairs, from one parse.
    ///
    /// A pair is an opener and its closer among the children of one node, matched on a stack:
    /// most grammars wrap a block in a node of its own (`{` first, `}` last), but some put the
    /// braces straight into the statement (Swift's `if`). A bracket inside a string or a comment
    /// is part of that token, never a child of its own, so the tree skips them with no lexing.
    /// A region is a pair spanning lines, from the opener's line to the line before the closer
    /// (amended 2026-10-16: it used to need the opener as its node's first child).
    static func structure(in text: String, language: Language) -> (regions: [FoldRegion], brackets: [BracketPair]) {
        let parser = Parser()
        guard (try? parser.setLanguage(language.treeSitterLanguage)) != nil, let tree = parser.parse(text),
            let root = tree.rootNode
        else { return ([], []) }
        var regions: [FoldRegion] = []
        var brackets: [BracketPair] = []
        var seen: Set<Int> = []
        visit(root) { node in
            var open: [(type: String, node: Node)] = []
            node.enumerateChildren { child in
                guard !child.isNamed, let type = child.nodeType else { return }
                if openers.contains(type) {
                    open.append((type, child))
                } else if let last = open.last, closers[last.type] == type {
                    open.removeLast()
                    brackets.append(BracketPair(open: last.node.range.location, close: child.range.location))
                    let region = FoldRegion(
                        first: Int(last.node.pointRange.lowerBound.row) + 1, last: Int(child.pointRange.lowerBound.row))
                    if region.last > region.first, seen.insert(region.first).inserted {
                        regions.append(region)
                    }
                }
            }
        }
        return (regions.sorted { $0.first < $1.first }, brackets.sorted { $0.open < $1.open })
    }

    /// editor R27: the innermost region around `line` (the one starting last).
    static func innermost(_ regions: [FoldRegion], containing line: Int) -> FoldRegion? {
        regions.filter { $0.contains(line: line) }.max { $0.first < $1.first }
    }

    /// editor R26: the lines hidden by the folded regions (their first line stays).
    static func hiddenLines(_ regions: [FoldRegion], folded: Set<Int>) -> IndexSet {
        var hidden = IndexSet()
        for region in regions where folded.contains(region.first) {
            hidden.insert(integersIn: (region.first + 1)...region.last)
        }
        return hidden
    }

    /// Pre-order, on an explicit stack: a pathologically nested tree must not overflow the
    /// call stack.
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
