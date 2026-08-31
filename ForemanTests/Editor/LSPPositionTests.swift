import Foundation
import LanguageServerProtocol
import Testing

@testable import Foreman

/// editor R38: LSP positions and `NSRange` locations, both ways.
///
/// The unit is the point: LSP's `character` counts UTF-16 code units by default, and so does
/// `NSString`. An emoji is two of them, and a test that used characters would pass on ASCII and
/// send the wrong column the first time someone wrote one.
struct LSPPositionTests {
    private let text = "let a = 1\nlet b = 2\n" as NSString

    @Test func mapsALocationToAZeroBasedLine() {
        #expect(TextEditing.lspPosition(at: 0, in: text) == Position(line: 0, character: 0))
        #expect(TextEditing.lspPosition(at: 4, in: text) == Position(line: 0, character: 4))
        #expect(TextEditing.lspPosition(at: 10, in: text) == Position(line: 1, character: 0))
        #expect(TextEditing.lspPosition(at: 14, in: text) == Position(line: 1, character: 4))
    }

    @Test func mapsAPositionBackToTheSameLocation() {
        for location in [0, 4, 9, 10, 14, 19] {
            let position = TextEditing.lspPosition(at: location, in: text)
            #expect(TextEditing.location(ofLSP: position, in: text) == location)
        }
    }

    /// An astral character is two UTF-16 code units: the column after it is 2, not 1.
    @Test func countsUTF16CodeUnitsNotCharacters() {
        let emoji = "let a = \"🚀\"\n" as NSString
        let afterEmoji = TextEditing.lspPosition(at: 11, in: emoji)
        #expect(afterEmoji == Position(line: 0, character: 11))
        #expect(TextEditing.location(ofLSP: afterEmoji, in: emoji) == 11)
    }

    /// The last line of a text ending in a newline is an empty one, and it has a position.
    @Test func placesTheEmptyLastLine() {
        #expect(TextEditing.lspPosition(at: text.length, in: text) == Position(line: 2, character: 0))
        #expect(TextEditing.location(ofLSP: Position(line: 2, character: 0), in: text) == text.length)
    }

    /// A position past the end, or before it, lands inside the text rather than crashing.
    @Test func clampsAPositionOutsideTheText() {
        #expect(TextEditing.location(ofLSP: Position(line: 99, character: 0), in: text) == text.length)
        #expect(TextEditing.location(ofLSP: Position(line: 0, character: 99), in: text) == 9)
        #expect(TextEditing.location(ofLSP: Position(line: -1, character: -1), in: text) == 0)
    }

    @Test func handlesAnEmptyText() {
        let empty = "" as NSString
        #expect(TextEditing.lspPosition(at: 0, in: empty) == Position(line: 0, character: 0))
        #expect(TextEditing.location(ofLSP: Position(line: 0, character: 0), in: empty) == 0)
    }
}
