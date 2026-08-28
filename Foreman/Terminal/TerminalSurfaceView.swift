import AppKit
import SwiftTerm

/// The SwiftTerm view of one process: PTY, process, rendering and input are the library's
/// (terminal, technical options); Foreman only adds the scrollback size and the bell as an event.
final class TerminalSurfaceView: LocalProcessTerminalView {
    /// terminal R14: the size of the scrollback.
    static let scrollbackLines = 10_000

    /// terminal R7: the bell marks the tab; there is no beep and no flash.
    var onBell: (() -> Void)?

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

    /// terminal R14: colors from `ThemeService`, converted here and only here (architecture:
    /// third-party types next to their use).
    func apply(_ palette: ThemeService.TerminalPalette, font: NSFont) {
        if self.font != font {
            self.font = font
        }
        nativeForegroundColor = palette.foreground
        nativeBackgroundColor = palette.background
        caretColor = palette.cursor
        selectedTextBackgroundColor = palette.selection
        installColors(palette.ansi.map(Self.color))
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
