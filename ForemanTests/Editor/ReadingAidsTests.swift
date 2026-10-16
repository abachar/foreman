import Foundation
import Testing

@testable import Foreman

/// Indent guides, the active block and matched brackets (editor R54, R55, M21 21.9).
struct ReadingAidsTests {
    @Test func levelsCountTheIndentAndBlankLinesTakeTheSmallerNeighbour() {
        let text = """
            class A {
                func f() {
                    if x {

                        y()
                    }
                }

                func g() {}
            }
            """
        #expect(IndentGuides.levels(of: text, width: 4) == [0, 1, 2, 2, 3, 2, 1, 1, 1, 0])
    }

    @Test func aTabCountsItsWidth() {
        #expect(IndentGuides.levels(of: "a\n\tb\n\t\tc\n  \td", width: 4) == [0, 1, 2, 1])
        #expect(IndentGuides.levels(of: "a\n  b\n    c", width: 2) == [0, 1, 2])
        #expect(IndentGuides.width(of: "\t") == 4)
        #expect(IndentGuides.width(of: "  ") == 2)
    }

    @Test func aLineGetsAGuidePerEnclosingLevelButTheOutermost() {
        #expect(IndentGuides.columns(level: 0, width: 4).isEmpty)
        #expect(IndentGuides.columns(level: 1, width: 4).isEmpty)
        #expect(IndentGuides.columns(level: 3, width: 4) == [4, 8])
    }

    @Test func theActiveGuideIsTheCaretsInnermostBlock() {
        // Lines 1…7 of the text above: class 1–10, f 2–7, if 3–6.
        let levels = [0, 1, 2, 2, 3, 2, 1, 1, 1, 0]
        let regions = [FoldRegion(first: 1, last: 10), FoldRegion(first: 2, last: 7), FoldRegion(first: 3, last: 6)]
        let guide = IndentGuides.activeGuide(regions: regions, caretLine: 5, levels: levels, width: 4)
        #expect(guide?.column == 8)
        #expect(guide?.lines == 4...5)
        #expect(IndentGuides.activeGuide(regions: regions, caretLine: 2, levels: levels, width: 4)?.column == 4)
        #expect(IndentGuides.activeGuide(regions: [], caretLine: 2, levels: levels, width: 4) == nil)
    }

    @Test func lineStartsFindTheLineOfAnOffset() {
        let starts = IndentGuides.lineStarts(of: "ab\ncd\n\nef" as NSString)
        #expect(starts == [0, 3, 6, 7])
        #expect(IndentGuides.line(at: 0, starts: starts) == 1)
        #expect(IndentGuides.line(at: 4, starts: starts) == 2)
        #expect(IndentGuides.line(at: 6, starts: starts) == 3)
        #expect(IndentGuides.line(at: 8, starts: starts) == 4)
    }

    @Test func bracketsMatchAcrossStringsAndComments() throws {
        let text = #"func f() { let s = "}{"; /* ) } */ g(a[1]) }"#
        let (_, pairs) = Folding.structure(in: text, language: .swift)
        let nsText = text as NSString
        func offset(_ needle: String, after start: Int = 0) -> Int {
            nsText.range(of: needle, range: NSRange(location: start, length: nsText.length - start)).location
        }
        let body = offset("{")
        let lastBrace = nsText.length - 1
        // The body's pair skips the braces of the string and of the comment.
        #expect(pairs.contains(BracketPair(open: body, close: lastBrace)))
        let call = offset("g(") + 1
        let match = try #require(BracketPair.match(pairs, caret: call + 1))
        #expect(match.open == call)
        #expect(nsText.substring(with: NSRange(location: match.close, length: 1)) == ")")
        // Before the caret first, then at it.
        #expect(BracketPair.match(pairs, caret: lastBrace + 1)?.open == body)
        #expect(BracketPair.match(pairs, caret: body)?.close == lastBrace)
        #expect(BracketPair.match(pairs, caret: offset("let")) == nil)
    }
}

/// The gutter's fold markers (editor R27 amended, M21 21.10).
struct FoldMarkersTests {
    @Test func openingOnTheFirstLineClosingOnTheCloserTheCaretsBlockActive() {
        let outer = FoldRegion(first: 1, last: 9)
        let inner = FoldRegion(first: 3, last: 5)
        let markers = FoldMarkers.markers(regions: [outer, inner], folded: [], active: inner)
        #expect(markers[1]?.kind == .open)
        #expect(markers[10]?.kind == .close)
        #expect(markers[3] == FoldMarkers.Marker(kind: .open, region: inner, isActive: true))
        #expect(markers[6] == FoldMarkers.Marker(kind: .close, region: inner, isActive: true))
        #expect(markers[1]?.isActive == false)
        #expect(markers.count == 4)
    }

    @Test func aFoldedRegionHasNoClosingMarkerAndAnOpenerWinsItsLine() {
        // `} else {`: the first block closes on the line the second opens.
        let first = FoldRegion(first: 1, last: 2)
        let second = FoldRegion(first: 3, last: 4)
        let markers = FoldMarkers.markers(regions: [first, second], folded: [3], active: nil)
        #expect(markers[3] == FoldMarkers.Marker(kind: .folded, region: second, isActive: false))
        #expect(markers[5] == nil)
        #expect(markers[1]?.kind == .open)
    }
}

/// The sticky lines (editor R56, M21 21.11).
struct StickyLinesTests {
    // class 1–40, method 3–20, if 5–9, method 22–39.
    private let regions = [
        FoldRegion(first: 1, last: 40), FoldRegion(first: 3, last: 20), FoldRegion(first: 5, last: 9),
        FoldRegion(first: 22, last: 39),
    ]

    @Test func theBlocksStartedAboveTheTopArePinnedOutermostFirst() {
        #expect(StickyLines.lines(topLine: 1, regions: regions).isEmpty)
        #expect(StickyLines.lines(topLine: 2, regions: regions) == [1])
        // The two pinned lines cover lines 4 and 5: the `if` opened on 5 joins them.
        #expect(StickyLines.lines(topLine: 4, regions: regions) == [1, 3, 5])
        #expect(StickyLines.lines(topLine: 25, regions: regions) == [1, 22])
        #expect(StickyLines.lines(topLine: 41, regions: regions).isEmpty)
        // A block about to end lets go: under the class's line, `if` 5–9 has only its closer left.
        #expect(StickyLines.lines(topLine: 9, regions: regions) == [1, 3])
    }

    @Test func threeAtMost() {
        let deep = (1...6).map { FoldRegion(first: $0, last: 100 - $0) }
        #expect(StickyLines.lines(topLine: 50, regions: deep) == [1, 2, 3])
        #expect(StickyLines.lines(topLine: 50, regions: deep, cap: 2) == [1, 2])
    }
}
