import Foundation
import Observation

/// One surface as the features and the view see it: a command, a folder, a state.
///
/// terminal R2, R5–R8. Driven by `TerminalService` from SwiftTerm's callbacks; it never touches a PTY.
@MainActor
@Observable
final class TerminalTab {
    let kind: String
    /// terminal R5: fixed, the feature's.
    let title: String
    let command: String
    let cwd: URL
    let env: [String: String]

    private(set) var state: TerminalState = .idle
    /// terminal R5: what the process pushed through OSC 0/2, shown as a tooltip only.
    private(set) var subtitle: String?
    /// terminal R7: bell or exit while the tab was inactive; cleared when it is activated.
    private(set) var isMarked = false
    /// Edge cases: the folder disappeared between two openings.
    private(set) var isCwdMissing: Bool
    /// Incremented on every new process, so the view swaps its surface (terminal R8).
    private(set) var generation = 0
    /// layout (status bar, 2026-10-16): the grid the surface last reported.
    private(set) var size: (columns: Int, rows: Int)?

    init(kind: String, title: String, command: String, cwd: URL, env: [String: String] = [:]) {
        self.kind = kind
        self.title = title
        self.command = command
        self.cwd = cwd
        self.env = env
        isCwdMissing = !Self.isDirectory(cwd)
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var pid: pid_t? {
        if case .running(let pid) = state { return pid }
        return nil
    }

    func didResize(columns: Int, rows: Int) {
        guard size?.columns != columns || size?.rows != rows else { return }
        size = (columns, rows)
    }

    // MARK: - Transitions (terminal R6–R8)

    func didStart(pid: pid_t) {
        state = .running(pid: pid)
        isMarked = false
        subtitle = nil
    }

    func didExit(_ exit: TerminalExit, isActive: Bool) {
        state = .exited(exit)
        if !isActive {
            isMarked = true
        }
    }

    func didRingBell(isActive: Bool) {
        if !isActive {
            isMarked = true
        }
    }

    func didActivate() {
        isMarked = false
    }

    func didSetTitle(_ title: String) {
        // An identical OSC 0/2 republishes nothing: `@Observable` notifies on `willSet`.
        let new = title.isEmpty ? nil : title
        guard new != subtitle else { return }
        subtitle = new
    }

    /// terminal R8: same command, same folder, a new PTY; refused while the folder is missing.
    func willRelaunch() throws(TerminalError) {
        isCwdMissing = !Self.isDirectory(cwd)
        guard !isCwdMissing else { throw .cwdMissing }
        generation += 1
        state = .idle
    }

    /// Follows symlinks (`/tmp`), unlike `URL.resourceValues`.
    private nonisolated static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
