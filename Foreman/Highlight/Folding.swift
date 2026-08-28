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

    /// editor R26, R13: the regions, `[]` when the grammar cannot parse.
    static func regions(in text: String, language: Language) -> [FoldRegion] {
        let parser = Parser()
        guard (try? parser.setLanguage(language.treeSitterLanguage)) != nil, let tree = parser.parse(text),
            let root = tree.rootNode
        else { return [] }
        var regions: [FoldRegion] = []
        var seen: Set<Int> = []
        visit(root) { node in
            guard node.isNamed, let first = node.firstChild, !first.isNamed, let opener = first.nodeType,
                openers.contains(opener), let last = node.lastChild, last.id != first.id
            else { return }
            let region = FoldRegion(
                first: Int(first.pointRange.lowerBound.row) + 1, last: Int(last.pointRange.lowerBound.row))
            guard region.last > region.first, seen.insert(region.first).inserted else { return }
            regions.append(region)
        }
        return regions.sorted { $0.first < $1.first }
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

    private static func visit(_ node: Node, _ body: (Node) -> Void) {
        body(node)
        node.enumerateChildren { visit($0, body) }
    }
}
