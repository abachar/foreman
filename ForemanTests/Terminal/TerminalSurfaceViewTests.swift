import AppKit
import Testing

@testable import Foreman

/// The `shift+enter` → `ESC CR` mapping (terminal R12, amended 2026-09-09).
struct TerminalSurfaceViewTests {
    private let returnKey: UInt16 = 36

    @Test func shiftEnterInsertsANewline() {
        #expect(TerminalSurfaceView.insertsNewline(keyCode: returnKey, modifiers: [.shift]))
        // Caps lock or a device-dependent bit changes nothing.
        #expect(TerminalSurfaceView.insertsNewline(keyCode: returnKey, modifiers: [.shift, .capsLock]))
    }

    @Test func everyOtherKeyKeepsSwiftTermsHandling() {
        #expect(!TerminalSurfaceView.insertsNewline(keyCode: returnKey, modifiers: []))
        #expect(!TerminalSurfaceView.insertsNewline(keyCode: returnKey, modifiers: [.shift, .command]))
        #expect(!TerminalSurfaceView.insertsNewline(keyCode: returnKey, modifiers: [.shift, .option]))
        #expect(!TerminalSurfaceView.insertsNewline(keyCode: returnKey, modifiers: [.shift, .control]))
        #expect(!TerminalSurfaceView.insertsNewline(keyCode: 0, modifiers: [.shift]))
    }
}
