import Foundation
import SwiftUI
import Testing

@testable import Foreman

/// The service without any process: tab identity, restoration, unknown ids (terminal R16, R17; product R7).
@MainActor
struct TerminalServiceTests {
    private let layout = LayoutManager()
    private let service: TerminalService

    init() {
        service = TerminalService(layout: layout, theme: ThemeService(), root: URL(filePath: "/tmp"))
    }

    @Test func unknownTabIsAnError() {
        let id = TabID()
        #expect(throws: TerminalError.noSuchTab) { try service.state(of: id) }
        #expect(throws: TerminalError.noSuchTab) { try service.relaunch(id) }
        #expect(throws: TerminalError.noSuchTab) { try service.signal(SIGINT, to: id) }
        #expect(service.view(for: id) == nil)
    }

    @Test func restoredTabIsIdleInItsFolderAndNotRun() throws {
        let id = TabID()
        _ = service.restore(id, kind: "agent.claude", title: "Claude", command: "claude", cwd: URL(filePath: "/tmp"))

        #expect(try service.state(of: id) == .idle)
        #expect(try service.pid(of: id) == nil)
        #expect(service.tab(id)?.isCwdMissing == false)
    }

    /// terminal R16: a tab with no live process is told, not silently written to.
    @Test func writingToARestoredTabIsRefused() {
        let id = TabID()
        _ = service.restore(id, kind: "agent.claude", title: "Claude", command: "claude", cwd: URL(filePath: "/tmp"))

        #expect(throws: TerminalError.notRunning) { try service.write(Array("@x ".utf8), to: id) }
        #expect(throws: TerminalError.noSuchTab) { try service.write(Array("@x ".utf8), to: TabID()) }
    }

    @Test func restoredTabInAMissingFolderCannotRelaunch() {
        let id = TabID()
        _ = service.restore(
            id, kind: "run.x", title: "x", command: "true", cwd: URL(filePath: "/tmp/foreman-gone-\(UUID().uuidString)")
        )

        #expect(service.tab(id)?.isCwdMissing == true)
        #expect(throws: TerminalError.cwdMissing) { try service.relaunch(id) }
    }

    @Test func registersTheTerminalShortcuts() {
        #expect(layout.shortcuts.shortcut(for: "terminal.clear") == Shortcut(parsing: "cmd+k"))
        #expect(layout.shortcuts.shortcut(for: "terminal.zoomIn") == Shortcut(parsing: "cmd+="))
        #expect(layout.shortcuts.shortcut(for: "terminal.zoomOut") == Shortcut(parsing: "cmd+-"))
        #expect(layout.shortcuts.problems.isEmpty)
    }

    @Test func closesWithoutAskingWhenNothingRuns() async throws {
        let id = TabID()
        _ = service.restore(id, kind: "agent.claude", title: "Claude", command: "claude", cwd: URL(filePath: "/tmp"))

        #expect(await service.confirmClose(id))
        #expect(await service.confirmClose(TabID()))

        var closed: [TerminalEvent] = []
        let events = service.events()
        service.closed(id)
        for await event in events.prefix(1) {
            closed.append(event)
        }
        #expect(closed == [.closed(id)])
        #expect(throws: TerminalError.noSuchTab) { try service.state(of: id) }
    }

    @Test func hangsUpARunningProcessAndKillsOnlyAfterTheGrace() {
        #expect(TerminalService.signalOnClose(.running(pid: 1)) == SIGHUP)
        #expect(TerminalService.signalOnClose(.idle) == nil)
        #expect(TerminalService.signalOnClose(.exited(.code(0))) == nil)
        #expect(TerminalService.signalAfterGrace(isStillRunning: true) == SIGKILL)
        #expect(TerminalService.signalAfterGrace(isStillRunning: false) == nil)
    }
}

/// terminal R7: when the Dock is asked to bounce.
struct TerminalAttentionTests {
    private let id = TabID()

    @Test func askedForABellOrAnExitWhileTheAppIsInTheBackground() {
        #expect(TerminalService.shouldRequestAttention(event: .bell(id), isAppActive: false))
        #expect(TerminalService.shouldRequestAttention(event: .exited(id, .code(0)), isAppActive: false))
        #expect(TerminalService.shouldRequestAttention(event: .exited(id, .signal(SIGINT)), isAppActive: false))
    }

    @Test func neverAskedWhileForemanIsTheActiveApplication() {
        #expect(!TerminalService.shouldRequestAttention(event: .bell(id), isAppActive: true))
        #expect(!TerminalService.shouldRequestAttention(event: .exited(id, .code(1)), isAppActive: true))
    }

    @Test func neverAskedForTheOtherEvents() {
        #expect(!TerminalService.shouldRequestAttention(event: .started(id, pid: 1), isAppActive: false))
        #expect(!TerminalService.shouldRequestAttention(event: .activated(id), isAppActive: false))
        #expect(!TerminalService.shouldRequestAttention(event: .closed(id), isAppActive: false))
    }
}
