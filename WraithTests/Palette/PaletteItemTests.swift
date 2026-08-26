import Foundation
import Testing

@testable import Wraith

/// The display highlight of a fuzzy match (editor R17).
struct PaletteItemTests {
    @Test func boldsTheQueryAsASubsequence() {
        let title = PaletteItem.highlighted("src/UserController.java", matching: "usrctrl")
        let bold = title.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(title[$0.range].characters) }
        #expect(bold.joined() == "UsrCtrl")
    }

    @Test func emptyQueryHighlightsNothing() {
        let title = PaletteItem.highlighted("a/b", matching: "")
        #expect(title.runs.allSatisfy { $0.inlinePresentationIntent == nil })
    }
}
