import Foundation
import Testing

@testable import Wraith

/// editor R26–R27: the regions of a few snippets, nesting, one-liners, `} else {`.
struct FoldingTests {
    @Test func typeScriptFunctionsObjectsAndCalls() {
        let text = """
            function a() {
              const o = {
                x: 1,
              };
              b(1,
                2);
              return o;
            }
            const one = { x: 1 };
            """
        let regions = Folding.regions(in: text, language: .typescript)
        #expect(regions == [FoldRegion(first: 1, last: 7), FoldRegion(first: 2, last: 3)])
    }

    @Test func elseKeepsItsLineVisible() {
        let text = """
            if (a) {
              x();
              y();
            } else {
              z();
              w();
            }
            """
        let regions = Folding.regions(in: text, language: .javascript)
        #expect(regions == [FoldRegion(first: 1, last: 3), FoldRegion(first: 4, last: 6)])
    }

    @Test func swiftAndJsonBlocks() {
        let swift = "struct A {\n    func f() {\n        g()\n    }\n}\n"
        #expect(
            Folding.regions(in: swift, language: .swift) == [
                FoldRegion(first: 1, last: 4), FoldRegion(first: 2, last: 3),
            ])
        let json = "{\n  \"a\": [\n    1,\n    2\n  ]\n}\n"
        #expect(
            Folding.regions(in: json, language: .json) == [
                FoldRegion(first: 1, last: 5), FoldRegion(first: 2, last: 4),
            ])
    }

    @Test func innermostRegionAndHiddenLines() {
        let regions = [FoldRegion(first: 1, last: 10), FoldRegion(first: 3, last: 5), FoldRegion(first: 12, last: 14)]
        #expect(Folding.innermost(regions, containing: 4) == regions[1])
        #expect(Folding.innermost(regions, containing: 8) == regions[0])
        #expect(Folding.innermost(regions, containing: 11) == nil)
        let hidden = Folding.hiddenLines(regions, folded: [3, 12])
        #expect(Array(hidden) == [4, 5, 13, 14])
    }

    @Test func hiddenCharactersFollowTheLines() {
        let text = "ab\ncd\nef\ngh" as NSString
        let characters = EditorTextView.Coordinator.characters(ofLines: IndexSet([2, 4]), in: text)
        #expect(Array(characters) == [3, 4, 5, 9, 10])
    }
}
