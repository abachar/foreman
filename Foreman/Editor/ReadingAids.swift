import Foundation

/// editor R55 (2026-10-16): a pair of matching brackets, by their UTF-16 offsets.
nonisolated struct BracketPair: Equatable, Hashable, Sendable {
    let open: Int
    let close: Int

    /// editor R55: the pair of the bracket just before the caret, else of the one at the caret.
    static func match(_ pairs: [BracketPair], caret: Int) -> BracketPair? {
        for offset in [caret - 1, caret] where offset >= 0 {
            if let pair = pairs.first(where: { $0.open == offset || $0.close == offset }) {
                return pair
            }
        }
        return nil
    }
}

/// editor R54 (2026-10-16, M21 21.9, view 02): the indent guides of a text.
nonisolated enum IndentGuides {
    /// How many indentation levels each line has, line `i + 1` at index `i`.
    ///
    /// A tab counts `tabWidth` columns, a level is `width` columns; a blank line takes the smaller
    /// level of the nearest non-blank lines around it, so a guide runs through the blank lines of
    /// a block and stops at the ones between two blocks.
    static func levels(of text: String, width: Int, tabWidth: Int = 4) -> [Int] {
        let width = max(width, 1)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var levels: [Int?] = lines.map { line in
            var columns = 0
            for character in line {
                if character == " " {
                    columns += 1
                } else if character == "\t" {
                    columns += tabWidth - columns % tabWidth
                } else {
                    return columns / width
                }
            }
            return nil
        }
        var previous: [Int?] = Array(repeating: nil, count: levels.count)
        var last: Int?
        for index in levels.indices {
            previous[index] = last
            if let level = levels[index] {
                last = level
            }
        }
        var next: Int?
        for index in levels.indices.reversed() {
            if let level = levels[index] {
                next = level
            } else {
                levels[index] = min(previous[index] ?? 0, next ?? 0)
            }
        }
        return levels.map { $0 ?? 0 }
    }

    /// The guides of a line at `level`: one at each enclosing level's column, the outermost
    /// (column 0) left out.
    static func columns(level: Int, width: Int) -> [Int] {
        level > 1 ? (1..<level).map { $0 * width } : []
    }

    /// editor R54: the guide of the caret's innermost block — the column of the block's first
    /// line's indentation, over the lines strictly inside it; `nil` outside any block.
    static func activeGuide(
        regions: [FoldRegion], caretLine: Int, levels: [Int], width: Int
    ) -> (column: Int, lines: ClosedRange<Int>)? {
        guard let region = Folding.innermost(regions, containing: caretLine), region.last - 1 >= region.first + 1,
            region.first - 1 < levels.count
        else { return nil }
        return (levels[region.first - 1] * width, (region.first + 1)...(region.last - 1))
    }

    /// Where each line starts, line `i + 1` at index `i`.
    static func lineStarts(of text: NSString) -> [Int] {
        var starts = [0]
        var index = 0
        while index < text.length {
            let range = text.range(of: "\n", options: [], range: NSRange(location: index, length: text.length - index))
            guard range.location != NSNotFound else { break }
            starts.append(NSMaxRange(range))
            index = NSMaxRange(range)
        }
        return starts
    }

    /// The 1-based line holding `offset`: the last start not past it.
    static func line(at offset: Int, starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }

    /// The columns of a level from the tab's indentation unit (`"\t"` counts `tabWidth`).
    static func width(of unit: String, tabWidth: Int = 4) -> Int {
        unit == "\t" ? tabWidth : max(unit.count, 1)
    }
}

/// editor R27 (amended 2026-10-16, M21 21.10, view 02): the gutter's fold markers.
nonisolated enum FoldMarkers {
    struct Marker: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            /// The region's first line, open: `⌄`.
            case open
            /// The region's first line, folded: `›`.
            case folded
            /// The line of the region's closer: `⌃`.
            case close
        }

        let kind: Kind
        /// The region the line belongs to, which a click folds or unfolds.
        let region: FoldRegion
        /// The caret's innermost block: drawn in `textPrimary`, the others in `textDisabled`.
        let isActive: Bool
    }

    /// The marker of each line: an opening one on a region's first line, a closing one on the
    /// line of its closer (the line after its last) unless it is folded; an opening marker wins
    /// a line that also closes a region (`} else {`).
    static func markers(regions: [FoldRegion], folded: Set<Int>, active: FoldRegion?) -> [Int: Marker] {
        var markers: [Int: Marker] = [:]
        for region in regions where !folded.contains(region.first) {
            markers[region.last + 1] = Marker(kind: .close, region: region, isActive: region == active)
        }
        for region in regions {
            markers[region.first] = Marker(
                kind: folded.contains(region.first) ? .folded : .open, region: region, isActive: region == active)
        }
        return markers
    }
}
