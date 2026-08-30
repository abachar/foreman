import Foundation
import Testing

@testable import Foreman

/// The state machine of a surface, driven by simulated events (terminal R6–R8, edge cases).
@MainActor
struct TerminalTabTests {
    private func tab(cwd: URL = URL(filePath: "/tmp")) -> TerminalTab {
        TerminalTab(kind: "agent.claude", title: "Claude", command: "claude", cwd: cwd)
    }

    @Test func goesIdleRunningExitedAndBackThroughRelaunch() throws {
        let tab = tab()
        #expect(tab.state == .idle)

        tab.didStart(pid: 42)
        #expect(tab.state == .running(pid: 42))
        #expect(tab.isRunning)
        #expect(tab.pid == 42)

        tab.didExit(.code(1), isActive: true)
        #expect(tab.state == .exited(.code(1)))
        #expect(!tab.isMarked)

        try tab.willRelaunch()
        #expect(tab.state == .idle)
        #expect(tab.generation == 1)

        tab.didStart(pid: 43)
        #expect(tab.state == .running(pid: 43))
    }

    @Test func marksAnInactiveTabOnBellOrExitUntilActivated() {
        let tab = tab()
        tab.didStart(pid: 1)

        tab.didRingBell(isActive: true)
        #expect(!tab.isMarked)
        tab.didRingBell(isActive: false)
        #expect(tab.isMarked)
        tab.didActivate()
        #expect(!tab.isMarked)

        tab.didExit(.signal(SIGINT), isActive: false)
        #expect(tab.isMarked)
        tab.didActivate()
        #expect(!tab.isMarked)
    }

    @Test func refusesToRelaunchInAMissingFolder() {
        let tab = tab(cwd: URL(filePath: "/tmp/foreman-gone-\(UUID().uuidString)"))

        #expect(tab.isCwdMissing)
        #expect(throws: TerminalError.cwdMissing) { try tab.willRelaunch() }
        #expect(tab.generation == 0)
    }

    /// terminal R12: the zoom is the tab's, over the theme's size, and stays readable.
    @Test func zoomAccumulatesOverTheThemeSizeAndStaysBounded() {
        let tab = tab()
        #expect(tab.zoomOffset == 0)

        tab.zoom(by: 1, base: 13)
        tab.zoom(by: 1, base: 13)
        #expect(tab.zoomOffset == 2)

        for _ in 0..<50 {
            tab.zoom(by: 1, base: 13)
        }
        #expect(tab.zoomOffset == TerminalTab.fontSizeRange.upperBound - 13)
        // One step back leaves the bound, it does not have to be pressed fifty times.
        tab.zoom(by: -1, base: 13)
        #expect(tab.zoomOffset == TerminalTab.fontSizeRange.upperBound - 14)

        for _ in 0..<50 {
            tab.zoom(by: -1, base: 13)
        }
        #expect(tab.zoomOffset == TerminalTab.fontSizeRange.lowerBound - 13)
    }

    @Test func keepsTheProcessTitleAsASubtitleOnly() {
        let tab = tab()
        tab.didSetTitle("vim README.md")
        #expect(tab.title == "Claude")
        #expect(tab.subtitle == "vim README.md")
        tab.didSetTitle("")
        #expect(tab.subtitle == nil)
    }
}

/// terminal R8, agents R8: what the status line under the surface says.
struct TerminalStatusLineTests {
    @Test func namesTheEndOfTheProcess() {
        #expect(TerminalTabView.statusLine(.exited(.code(0))) == "exited · code 0")
        #expect(TerminalTabView.statusLine(.exited(.signal(SIGINT))) == "exited · signal SIGINT")
    }

    @Test func offersTheBarToARestoredTabAndHidesItWhileRunning() {
        #expect(TerminalTabView.statusLine(.idle) == "not started")
        #expect(TerminalTabView.statusLine(.running(pid: 1)) == nil)
    }
}

/// Decoding of the `wait(2)` status SwiftTerm reports (terminal R6, R8).
struct TerminalExitTests {
    @Test func decodesExitCodesAndSignals() {
        #expect(TerminalExit(waitStatus: 0) == .code(0))
        #expect(TerminalExit(waitStatus: 127 << 8) == .code(127))
        #expect(TerminalExit(waitStatus: SIGINT) == .signal(SIGINT))
        #expect(TerminalExit(waitStatus: nil) == .signal(SIGKILL))
    }

    @Test func labelsForTheStatusLine() {
        #expect(TerminalExit.code(1).label == "code 1")
        #expect(TerminalExit.signal(SIGINT).label == "signal SIGINT")
        #expect(TerminalExit.signal(31).label == "signal 31")
    }
}
