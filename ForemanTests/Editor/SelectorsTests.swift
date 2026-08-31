import Foundation
import Testing

@testable import Foreman

/// editor R47, R48: what a stylesheet defines and what an HTML attribute asks for, off the trees.
struct SelectorsTests {
    // MARK: - The stylesheet (R47)

    @Test func readsClassesAndIds() {
        let css = """
            .card { color: red; }
            #main { color: blue; }
            """
        #expect(
            Selectors.definitions(in: css) == [
                Selectors.Definition(name: "card", kind: .classSelector, line: 1),
                Selectors.Definition(name: "main", kind: .idSelector, line: 2),
            ])
    }

    /// A compound selector defines each name it holds — the tree gives them separately.
    @Test func readsEveryNameOfACompoundSelector() {
        let names = Selectors.definitions(in: ".card .title { }\na.btn:hover { }").map(\.name)
        #expect(names == ["card", "title", "btn"])
    }

    /// The grammar names a pseudo-class `class_name` as well: without the guard, `:hover`
    /// would be indexed and `class="hover"` would jump to it.
    @Test func ignoresAPseudoClassAndAPseudoElement() {
        let names = Selectors.definitions(in: ".btn:hover { }\n.card::before { content: \"\"; }").map(\.name)
        #expect(names == ["btn", "card"])
    }

    /// Inside a media query the rule is nested, and it still defines its class.
    @Test func readsThroughAMediaQuery() {
        let css = "@media (min-width: 40em) {\n  .wide { display: block; }\n}"
        #expect(
            Selectors.definitions(in: css) == [Selectors.Definition(name: "wide", kind: .classSelector, line: 2)])
    }

    /// A name in a comment or in a string is not a definition — the reason this reads the tree.
    @Test func ignoresACommentAndAContentString() {
        let css = "/* .ghost { } */\n.real { content: \".fake\"; }"
        #expect(Selectors.definitions(in: css).map(\.name) == ["real"])
    }

    @Test func findsNothingInAnEmptyStylesheet() {
        #expect(Selectors.definitions(in: "").isEmpty)
    }

    // MARK: - The HTML attribute (R48)

    private let html = """
        <div class="btn btn-primary" id="hero">
          <p>text</p>
        </div>
        """

    @Test func readsTheClassUnderThePointer() {
        let text = html as NSString
        let second = text.range(of: "btn-primary").location + 2
        #expect(
            Selectors.reference(at: second, in: html)
                == Selectors.Reference(name: "btn-primary", kind: .classSelector))
    }

    /// A class list has several names and a click means the one it landed on, not the first.
    @Test func picksTheNameTheClickLandedOn() {
        let text = html as NSString
        let first = text.range(of: "\"btn btn-primary\"").location + 2
        #expect(Selectors.reference(at: first, in: html)?.name == "btn")
    }

    @Test func readsAnId() {
        let text = html as NSString
        #expect(
            Selectors.reference(at: text.range(of: "hero").location + 1, in: html)
                == Selectors.Reference(name: "hero", kind: .idSelector))
    }

    /// Anywhere else in the file — a tag, the text, another attribute — resolves to nothing.
    @Test func ignoresWhatIsNotAClassOrAnId() {
        let text = html as NSString
        #expect(Selectors.reference(at: text.range(of: "<p>").location + 1, in: html) == nil)
        #expect(Selectors.reference(at: text.range(of: "text").location + 1, in: html) == nil)
    }

    @Test func ignoresAnEmptyAttribute() {
        let empty = "<div class=\"\"></div>"
        #expect(Selectors.reference(at: 12, in: empty) == nil)
    }

    // MARK: - The word under a location

    @Test func takesTheWordUnderALocation() {
        let text = "btn btn-primary  wide" as NSString
        let bounds = NSRange(location: 0, length: text.length)
        #expect(Selectors.word(at: 0, in: text, within: bounds) == "btn")
        #expect(Selectors.word(at: 6, in: text, within: bounds) == "btn-primary")
        #expect(Selectors.word(at: 16, in: text, within: bounds).isEmpty)
        #expect(Selectors.word(at: 18, in: text, within: bounds) == "wide")
    }
}
