import AppKit
import SwiftTerm

/// The SwiftTerm view of one process: PTY, process, rendering and input are the library's
/// (terminal, technical options); Foreman only adds the scrollback size and the bell as an event.
final class TerminalSurfaceView: LocalProcessTerminalView {
    /// terminal R14: the size of the scrollback.
    static let scrollbackLines = 10_000

    /// terminal R7: the bell marks the tab; there is no beep and no flash.
    var onBell: (() -> Void)?

    /// How far `cmd+=` / `cmd+-` moved this surface from the theme's size, in points.
    ///
    /// Kept here and not on the font: every `apply` reinstalls the theme's font, so a zoom stored
    /// nowhere was undone by the next config reload or appearance change (audit T1).
    var zoomOffset: CGFloat = 0

    init(font: NSFont) {
        super.init(frame: .zero, font: font, options: TerminalOptions(scrollback: Self.scrollbackLines))
        bellStyle = .none
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func bell(source: Terminal) {
        onBell?()
    }

    /// terminal R12 (amended 2026-09-09, issue #4): `shift+enter` reaches the process as `ESC CR`,
    /// which the agent TUIs (Claude Code…) read as "insert a newline" — a bare `CR` submits.
    ///
    /// A local monitor, as `ShortcutRegistry`: SwiftTerm's `keyDown` is not `open`, and AppKit
    /// sends `performKeyEquivalent` for `cmd+…` keys only (checked 2026-09-10). A TUI that
    /// enabled the kitty keyboard protocol already receives `shift+enter` as `CSI 13;2u`.
    private var newlineMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let newlineMonitor {
            NSEvent.removeMonitor(newlineMonitor)
            self.newlineMonitor = nil
        }
        guard window != nil else { return }
        newlineMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window, event.window === window, window.firstResponder === self,
                terminal.keyboardEnhancementFlags.isEmpty,
                Self.insertsNewline(keyCode: event.keyCode, modifiers: event.modifierFlags)
            else { return event }
            send([0x1b, 0x0d])
            return nil
        }
    }

    /// `shift+enter` and nothing else: `cmd`/`opt`/`ctrl` combinations keep SwiftTerm's handling.
    nonisolated static func insertsNewline(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        keyCode == 36 && modifiers.contains(.shift)
            && modifiers.isDisjoint(with: [.command, .option, .control])
    }

    /// terminal R14: colors from `ThemeService`, converted here and only here (architecture:
    /// third-party types next to their use).
    func apply(_ palette: ThemeService.TerminalPalette, font: NSFont) {
        let zoomed = Self.zoomed(font, by: zoomOffset)
        if self.font != zoomed {
            self.font = zoomed
        }
        nativeForegroundColor = palette.foreground
        nativeBackgroundColor = palette.background
        caretColor = palette.cursor
        selectedTextBackgroundColor = palette.selection
        installColors(palette.ansi.map(Self.color))
    }

    /// terminal, zoom: the theme's font moved by `offset`, within readable bounds.
    nonisolated static func zoomed(_ font: NSFont, by offset: CGFloat) -> NSFont {
        let size = min(max(font.pointSize + offset, 8), 32)
        guard size != font.pointSize else { return font }
        return NSFont(descriptor: font.fontDescriptor, size: size) ?? font
    }

    nonisolated static func color(_ color: NSColor) -> Color {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        return Color(
            red: UInt16(max(0, min(1, srgb.redComponent)) * 65535),
            green: UInt16(max(0, min(1, srgb.greenComponent)) * 65535),
            blue: UInt16(max(0, min(1, srgb.blueComponent)) * 65535))
    }

    func start(_ launch: TerminalLaunch) {
        startProcess(
            executable: launch.executable, args: launch.arguments, environment: launch.environment,
            execName: nil, currentDirectory: launch.currentDirectory)
    }
}
