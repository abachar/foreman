import Foundation
import Testing

@testable import Foreman

/// The pure editing commands (editor R6, R8).
struct TextEditingTests {
    @Test func detectsIndentOnTheFirstLines() {
        #expect(TextEditing.detectIndent("a\n  b\n    c\n") == "  ")
        #expect(TextEditing.detectIndent("a\n\tb\n\tc\n  d\n") == "\t")
        #expect(TextEditing.detectIndent("no indent\n") == "    ")
        #expect(TextEditing.detectIndent("") == "    ")
    }

    @Test func newlineKeepsTheIndentOfTheLine() {
        let edit = TextEditing.newline(at: NSRange(location: 8, length: 0), in: "    let x = 1")
        #expect(edit.replacement == "\n    ")
        #expect(edit.selection == NSRange(location: 13, length: 0))
    }

    @Test func indentsAndOutdentsEverySelectedLine() {
        let text: NSString = "a\nb\n\nc\n"
        let indented = TextEditing.indent(NSRange(location: 0, length: 4), in: text, unit: "  ", outdent: false)
        #expect(indented.replacement == "  a\n  b\n")
        #expect(indented.range == NSRange(location: 0, length: 4))
        let blank = TextEditing.indent(NSRange(location: 0, length: 5), in: text, unit: "  ", outdent: false)
        #expect(blank.replacement == "  a\n  b\n\n")
        let outdented = TextEditing.indent(
            NSRange(location: 0, length: 9), in: "  a\n b\nc\n", unit: "  ", outdent: true)
        #expect(outdented.replacement == "a\nb\nc\n")
    }

    @Test func togglesLineComments() {
        let commented = TextEditing.toggleComment(
            NSRange(location: 0, length: 1), in: "  let x\n  let y\n", prefix: "//")
        #expect(commented.replacement == "  // let x\n")
        let both = TextEditing.toggleComment(NSRange(location: 0, length: 16), in: "  let x\n    let y\n", prefix: "//")
        #expect(both.replacement == "  // let x\n  //   let y\n")
        let removed = TextEditing.toggleComment(
            NSRange(location: 0, length: 20), in: "  // let x\n  //let y\n", prefix: "//")
        #expect(removed.replacement == "  let x\n  let y\n")
    }

    @Test func movesLinesUpAndDown() throws {
        let text: NSString = "a\nb\nc"
        let down = try #require(TextEditing.moveLines(NSRange(location: 0, length: 0), in: text, up: false))
        #expect(down.range == NSRange(location: 0, length: 4))
        #expect(down.replacement == "b\na\n")
        #expect(down.selection == NSRange(location: 2, length: 2))
        let last = try #require(TextEditing.moveLines(NSRange(location: 4, length: 0), in: text, up: true))
        #expect(last.replacement == "c\nb")
        #expect(TextEditing.moveLines(NSRange(location: 0, length: 0), in: text, up: true) == nil)
        #expect(TextEditing.moveLines(NSRange(location: 4, length: 0), in: text, up: false) == nil)
    }

    @Test func finalNewlineAndLineLocation() {
        #expect(TextEditing.withFinalNewline("a") == "a\n")
        #expect(TextEditing.withFinalNewline("a\n") == "a\n")
        #expect(TextEditing.withFinalNewline("") == "")
        #expect(TextEditing.location(ofLine: 3, in: "ab\ncd\nef") == 6)
        #expect(TextEditing.location(ofLine: 9, in: "ab\ncd\nef") == 8)
    }
}

/// agents R10b: the lines of a selection.
struct SelectedLinesTests {
    let text = "one\ntwo\nthree\n" as NSString

    @Test func caretHasNoLines() {
        #expect(TextEditing.selectedLines(NSRange(location: 5, length: 0), in: text) == nil)
    }

    @Test func selectionCoversItsLines() {
        #expect(TextEditing.selectedLines(NSRange(location: 1, length: 2), in: text) == 1...1)
        #expect(TextEditing.selectedLines(NSRange(location: 1, length: 6), in: text) == 1...2)
    }

    @Test func endAtColumnZeroExcludesThatLine() {
        #expect(TextEditing.selectedLines(NSRange(location: 0, length: 4), in: text) == 1...1)
        #expect(TextEditing.selectedLines(NSRange(location: 4, length: 4), in: text) == 2...2)
    }
}
