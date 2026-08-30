import AppKit
import Testing

@testable import Foreman

/// `return`, `cmd+return` and `opt+return` are three different choices (editor R17, run R6).
struct PalettePanelTests {
    @Test func returnKeyDependsOnTheModifiers() {
        #expect(PalettePanel.returnKey([]) == .return(newGroup: false))
        #expect(PalettePanel.returnKey(.command) == .return(newGroup: true))
        #expect(PalettePanel.returnKey(.option) == .secondary)
        #expect(PalettePanel.returnKey([.option, .command]) == .secondary)
    }
}

/// editor R17: the keys the palette answers, and the ones its field must receive.
struct PaletteKeyTests {
    private func key(
        _ special: NSEvent.SpecialKey?, characters: String? = nil, _ modifiers: NSEvent.ModifierFlags = []
    ) -> PalettePanel.Key? {
        PalettePanel.key(for: special, characters: characters, modifiers: modifiers)
    }

    @Test func arrowsNavigateOnlyWhenTheyAreNotTheFields() {
        #expect(key(.upArrow) == .up)
        #expect(key(.downArrow) == .down)
        // `shift+↑` selects the field's text and `cmd+↓` moves in it: neither is a move in the list.
        #expect(key(.upArrow, .shift) == nil)
        #expect(key(.downArrow, .command) == nil)
        #expect(key(.leftArrow) == nil)
    }

    @Test func bothReturnKeysChooseWithTheirModifiers() {
        #expect(key(.carriageReturn) == .return(newGroup: false))
        #expect(key(.enter) == .return(newGroup: false))
        #expect(key(.carriageReturn, .command) == .return(newGroup: true))
        #expect(key(.enter, .option) == .secondary)
    }

    @Test func escapeClosesAndTheRestIsTyping() {
        #expect(key(nil, characters: "\u{1B}") == .escape)
        // `opt+escape` completes a word in the field.
        #expect(key(nil, characters: "\u{1B}", .option) == nil)
        #expect(key(nil, characters: "a") == nil)
        #expect(key(.tab) == nil)
    }
}
