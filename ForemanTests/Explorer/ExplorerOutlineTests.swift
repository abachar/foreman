import AppKit
import Testing

@testable import Foreman

/// explorer R12, R21: the keys the tree answers before the outline view does.
struct ExplorerOutlineKeysTests {
    private typealias Key = KeyboardOutlineView.Key

    private func key(_ special: NSEvent.SpecialKey?, _ modifiers: NSEvent.ModifierFlags = []) -> Key? {
        KeyboardOutlineView.key(for: special, modifiers: modifiers)
    }

    @Test func bothReturnKeysOpen() {
        #expect(key(.carriageReturn) == .open)
        #expect(key(.enter) == .open)
        #expect(key(.carriageReturn, [.command]) == .open)
    }

    @Test func renameAndDeleteNeedTheirModifier() {
        #expect(key(.f6, [.shift]) == .rename)
        #expect(key(.f6) == nil)
        #expect(key(.delete, [.command]) == .commandDelete)
        #expect(key(.delete) == nil)
    }

    @Test func everythingElseIsTheOutlineViews() {
        #expect(key(nil) == nil)
        #expect(key(.tab) == nil)
        #expect(key(.upArrow) == nil)
        #expect(key(.deleteForward, [.command]) == nil)
    }
}
