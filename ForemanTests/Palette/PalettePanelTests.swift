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
