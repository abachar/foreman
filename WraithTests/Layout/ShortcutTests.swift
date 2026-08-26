import Foundation
import Testing

@testable import Wraith

/// The `config` notation of shortcuts.
struct ShortcutTests {
    @Test(arguments: [
        ("cmd+shift+g", "g", Shortcut.Modifiers([.command, .shift])),
        ("CMD+ALT+Left", "left", Shortcut.Modifiers([.command, .option])),
        ("escape", "escape", Shortcut.Modifiers([])),
        ("ctrl+[", "[", Shortcut.Modifiers.control),
        ("cmd+9", "9", Shortcut.Modifiers.command),
    ])
    func parsesModifiersAndKey(text: String, key: String, modifiers: Shortcut.Modifiers) {
        let shortcut = Shortcut(parsing: text)

        #expect(shortcut?.key == key)
        #expect(shortcut?.modifiers == modifiers)
    }

    @Test(arguments: ["", "cmd+", "+g", "cmd+cmd+g", "super+g", "cmd+gg", "cmd+home"])
    func rejectsWhatIsNotAShortcut(text: String) {
        #expect(Shortcut(parsing: text) == nil)
    }

    @Test func printsInTheSameNotation() {
        #expect(Shortcut(parsing: "shift+cmd+G")?.description == "cmd+shift+g")
    }
}
