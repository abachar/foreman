import AppKit
import Metal
import SwiftTerm
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

/// terminal R14 (M23 23.6): the surface draws through SwiftTerm's Metal renderer once it is in a
/// window, and keeps it across a theme or zoom change.
@MainActor
struct TerminalSurfaceViewRendererTests {
    @Test func usesTheMetalRendererOnceInAWindow() {
        // A machine without a GPU (a CI runner) keeps CoreGraphics: nothing to check there.
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let surface = TerminalSurfaceView(font: .monospacedSystemFont(ofSize: 12, weight: .regular))
        #expect(!surface.isUsingMetalRenderer, "SwiftTerm needs a window before Metal")

        // Owned by the test and never ordered in, as `ShortcutMonitorLifetimeTests.window()`.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = surface
        #expect(surface.isUsingMetalRenderer)

        // A theme change, then a zoom, set the font and the colours after the renderer exists.
        surface.apply(
            ThemeService().terminalPalette(dark: true), font: .monospacedSystemFont(ofSize: 14, weight: .regular))
        surface.font = TerminalSurfaceView.zoomed(surface.font, by: 2)
        #expect(surface.isUsingMetalRenderer)
        #expect(surface.font.pointSize == 16)
    }
}
