import AppKit
import SwiftTerm

/// The SwiftTerm view of one process: PTY, process, rendering and input are the library's
/// (terminal, technical options); Wraith only adds the scrollback size and the bell as an event.
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

    func start(_ launch: TerminalLaunch) {
        startProcess(
            executable: launch.executable, args: launch.arguments, environment: launch.environment,
            execName: nil, currentDirectory: launch.currentDirectory)
    }
}
