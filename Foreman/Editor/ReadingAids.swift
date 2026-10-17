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
    /// editor R54, R6 (audit 2026-10-17 U2, M23 23.8): one UTF-8 pass gives the lines' indentation
    /// levels and their UTF-16 starts; a grapheme walk of a 55 KB file cost 10 ms a keystroke.
    nonisolated struct Scan: Equatable, Sendable {
        /// How many indentation levels each line has, line `i + 1` at index `i`.
        let levels: [Int]
        /// Where each line starts as a UTF-16 offset, line `i + 1` at index `i`.
        let lineStarts: [Int]
    }

    /// How many indentation levels each line has, line `i + 1` at index `i`.
    static func levels(of text: String, width: Int, tabWidth: Int = 4) -> [Int] {
        scan(text, width: width, tabWidth: tabWidth).levels
    }

    /// The indentation levels and the line starts of a text, from one pass over its UTF-8 bytes.
    ///
    /// A tab counts `tabWidth` columns, a level is `width` columns; a blank line takes the smaller
    /// level of the nearest non-blank lines around it, so a guide runs through the blank lines of
    /// a block and stops at the ones between two blocks. A line's indentation is ASCII spaces and
    /// tabs, so bytes are exact: any other byte (a `\r`, the lead byte of `é`) ends it.
    static func scan(_ text: String, width: Int, tabWidth: Int = 4) -> Scan {
        var text = text
        // `NSTextView.string` bridges an `NSString`: one copy to native UTF-8 makes it contiguous.
        text.makeContiguousUTF8()
        let scanBytes = { (bytes: UnsafeBufferPointer<UInt8>) in scan(bytes: bytes, width: width, tabWidth: tabWidth) }
        return text.utf8.withContiguousStorageIfAvailable(scanBytes)
            ?? Array(text.utf8).withUnsafeBufferPointer(scanBytes)
    }

    private static func scan(bytes: UnsafeBufferPointer<UInt8>, width: Int, tabWidth: Int) -> Scan {
        let width = max(width, 1)
        var levels: [Int?] = []
        var lineStarts = [0]
        var utf16Offset = 0
        var columns = 0
        // `nil` while the line is still in its indentation.
        var level: Int?
        for byte in bytes {
            if byte == UInt8(ascii: "\n") {
                levels.append(level)
                level = nil
                columns = 0
                utf16Offset += 1
                lineStarts.append(utf16Offset)
                continue
            }
            if level == nil {
                if byte == UInt8(ascii: " ") {
                    columns += 1
                } else if byte == UInt8(ascii: "\t") {
                    columns += tabWidth - columns % tabWidth
                } else {
                    level = columns / width
                }
            }
            // UTF-16 units: one per ASCII or lead byte, two for a 4-byte lead, none for a continuation.
            if byte < 0x80 || byte >= 0xC0 {
                utf16Offset += byte >= 0xF0 ? 2 : 1
            }
        }
        levels.append(level)
        return Scan(levels: filled(levels), lineStarts: lineStarts)
    }

    /// A blank line (`nil`) takes the smaller level of the nearest non-blank lines around it.
    private static func filled(_ raw: [Int?]) -> [Int] {
        var levels = raw
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

/// editor R56 (2026-10-16, M21 21.11, view 02): the sticky lines of an editor.
nonisolated enum StickyLines {
    /// editor R56, decision 2026-10-16: three at most.
    static let cap = 3

    /// The first lines of the blocks the top of the editor is in, outermost first, `cap` at most.
    ///
    /// The pinned lines cover the first visible lines, so each slot is checked against the line
    /// it covers: a block is pinned in slot `k` when its first line is above `topLine + k` and its
    /// body still reaches the line under the slot — so a block about to end lets go of its line
    /// instead of covering its own last lines.
    static func lines(topLine: Int, regions: [FoldRegion], cap: Int = StickyLines.cap) -> [Int] {
        var pinned: [Int] = []
        for region in regions.sorted(by: { $0.first < $1.first }) where pinned.count < cap {
            let slot = topLine + pinned.count
            if region.first < slot, region.last >= slot + 1 {
                pinned.append(region.first)
            }
        }
        return pinned
    }
}
