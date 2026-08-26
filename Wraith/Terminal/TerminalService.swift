import AppKit
import Foundation
import SwiftTerm
import SwiftUI
import os

/// The surfaces of one window (terminal R16–R18): created once in `App`, injected to the
/// features, which own the tab kinds (`agent.<id>`, `run.<id>`) and forward `view`, `confirmClose`
/// and `closed` from their `CenterTabDescriptor`.
@MainActor
final class TerminalService {
    private let layout: LayoutManager
    private let theme: ThemeService
    private let root: URL
    private var tabs: [TabID: TerminalTab] = [:]
    private var surfaces: [TabID: TerminalSurfaceView] = [:]
    /// terminal R11: surfaces of closed tabs, kept until their process is gone.
    private var closing: [TabID: TerminalSurfaceView] = [:]
    /// terminal R11: the grace period before `SIGKILL`, only on closing.
    static let closeGrace: Duration = .seconds(5)
    /// The tab `spawn` is creating: the feature's `makeView` asks for its view before `openTab` returns.
    private var opening: TerminalTab?
    private var subscribers: [UUID: AsyncStream<TerminalEvent>.Continuation] = [:]
    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "terminal")

    init(layout: LayoutManager, theme: ThemeService, root: URL) {
        self.layout = layout
        self.theme = theme
        self.root = root
        registerActions()
    }

    isolated deinit {
        // terminal R11: the window goes, its processes get SIGHUP; nothing survives the service.
        for surface in surfaces.values.filter({ $0.process.running }) + closing.values {
            killpg(surface.process.shellPid, SIGHUP)
        }
        for continuation in subscribers.values {
            continuation.finish()
        }
    }

    // MARK: - Features (terminal R16, R17)

    /// terminal R16: a stream per consumer, finished with the service.
    func events() -> AsyncStream<TerminalEvent> {
        let (stream, continuation) = AsyncStream<TerminalEvent>.makeStream()
        let key = UUID()
        subscribers[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers[key] = nil }
        }
        return stream
    }

    /// Opens a tab of `kind` in the active group and starts the process.
    ///
    /// `nil` when the layout refuses (unknown kind). The feature's `makeView` must call `view(for:)`.
    func spawn(command: String, cwd: URL, env: [String: String] = [:], kind: String, title: String) -> TabID? {
        let tab = TerminalTab(kind: kind, title: title, command: command, cwd: cwd, env: env)
        opening = tab
        defer { opening = nil }
        guard let id = layout.openTab(kind: kind, title: title, payload: "") else { return nil }
        launch(id, tab)
        return id
    }

    /// The view of the tab `spawn` is opening, or of a tab already known; `nil` otherwise.
    func view(for id: TabID) -> AnyView? {
        if let opening, tabs[id] == nil {
            tabs[id] = opening
        }
        guard tabs[id] != nil else { return nil }
        return AnyView(TerminalTabView(id: id, service: self))
    }

    /// product R7, terminal US6: a restored tab is `idle` in its folder, the command not run.
    func restore(
        _ id: TabID, kind: String, title: String, command: String, cwd: URL, env: [String: String] = [:]
    ) -> AnyView {
        tabs[id] = TerminalTab(kind: kind, title: title, command: command, cwd: cwd, env: env)
        return AnyView(TerminalTabView(id: id, service: self))
    }

    func tab(_ id: TabID) -> TerminalTab? {
        tabs[id]
    }

    func state(of id: TabID) throws(TerminalError) -> TerminalState {
        try known(id).state
    }

    func pid(of id: TabID) throws(TerminalError) -> pid_t? {
        try known(id).pid
    }

    /// terminal R8: same command, same folder, a new surface in the same tab.
    func relaunch(_ id: TabID) throws(TerminalError) {
        let tab = try known(id)
        guard !tab.isRunning else { return }
        try tab.willRelaunch()
        surfaces[id] = nil
        launch(id, tab)
    }

    /// terminal R9: to the process group of the PTY; never `SIGKILL` from here.
    func signal(_ signal: Int32, to id: TabID) throws(TerminalError) {
        guard let pid = try known(id).pid else { return }
        killpg(pid, signal)
    }

    /// terminal R16: raw input, for a feature that must type into the process.
    func write(_ bytes: [UInt8], to id: TabID) throws(TerminalError) {
        _ = try known(id)
        surfaces[id]?.send(bytes)
    }

    /// terminal R7: the view reports that its tab is shown.
    func activated(_ id: TabID) {
        guard let tab = tabs[id] else { return }
        tab.didActivate()
        syncBadge(id, tab)
    }

    // MARK: - Closing (terminal R10, R11)

    /// terminal R10, layout R15: a running process asks before the tab closes.
    func confirmClose(_ id: TabID) async -> Bool {
        guard let tab = tabs[id], tab.isRunning, let window = surfaces[id]?.window ?? NSApp.keyWindow else {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "\(tab.title) is still running"
        alert.informativeText = "Closing the tab stops the process."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    /// terminal R11: the tab left the layout; hang up the process group, kill it only if it is still
    /// there after the grace period, then let the view close the PTY.
    func closed(_ id: TabID) {
        guard let tab = tabs[id] else { return }
        tabs[id] = nil
        let surface = surfaces.removeValue(forKey: id)
        publish(.closed(id))
        guard let surface, let pid = tab.pid, let signal = Self.signalOnClose(tab.state) else { return }
        killpg(pid, signal)
        closing[id] = surface
        Task { [weak self] in
            try? await Task.sleep(for: Self.closeGrace)
            guard let self else { return }
            if let signal = Self.signalAfterGrace(isStillRunning: surface.process.running) {
                killpg(pid, signal)
            }
            closing[id] = nil
        }
    }

    /// terminal R11: `SIGHUP` to a running process; nothing to an idle or exited one.
    nonisolated static func signalOnClose(_ state: TerminalState) -> Int32? {
        if case .running = state { return SIGHUP }
        return nil
    }

    /// terminal R11: `SIGKILL` only when the process ignored the hang-up for the whole grace period.
    nonisolated static func signalAfterGrace(isStillRunning: Bool) -> Int32? {
        isStillRunning ? SIGKILL : nil
    }

    private func known(_ id: TabID) throws(TerminalError) -> TerminalTab {
        guard let tab = tabs[id] else { throw .noSuchTab }
        return tab
    }

    // MARK: - Surfaces

    /// The SwiftTerm view of a tab, created on first display; a new one after each relaunch.
    func surface(for id: TabID) -> TerminalSurfaceView? {
        guard tabs[id] != nil else { return nil }
        if let surface = surfaces[id] {
            return surface
        }
        let surface = TerminalSurfaceView(font: theme.editorFont)
        surface.processDelegate = self
        surface.onBell = { [weak self] in self?.bell(id) }
        surfaces[id] = surface
        return surface
    }

    private func launch(_ id: TabID, _ tab: TerminalTab) {
        guard let surface = surface(for: id) else { return }
        let environment = ProcessInfo.processInfo.environment
        let launch = TerminalLaunch(
            command: tab.command, cwd: tab.cwd, root: root, extraEnvironment: tab.env,
            shell: environment["SHELL"], baseEnvironment: environment,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
        surface.start(launch)
        let pid = surface.process.shellPid
        guard pid > 0 else {
            logger.error("process not started for \(tab.kind, privacy: .public)")
            tab.didExit(.signal(SIGKILL), isActive: isActive(id))
            syncBadge(id, tab)
            return
        }
        tab.didStart(pid: pid)
        syncBadge(id, tab)
        publish(.started(id, pid: pid))
    }

    private func bell(_ id: TabID) {
        guard let tab = tabs[id] else { return }
        tab.didRingBell(isActive: isActive(id))
        syncBadge(id, tab)
        publish(.bell(id))
    }

    private func isActive(_ id: TabID) -> Bool {
        layout.model.active.active?.id == id
    }

    /// terminal R7, R10: running → green dot and dirty; marked → orange dot.
    private func syncBadge(_ id: TabID, _ tab: TerminalTab) {
        let badge: ToolbarBadge = tab.isRunning ? .dot(.green) : (tab.isMarked ? .dot(.orange) : .none)
        layout.update(id, title: tab.title, isDirty: tab.isRunning, badge: badge)
    }

    private func publish(_ event: TerminalEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    // MARK: - Shortcuts (terminal R12)

    private func registerActions() {
        let actions: [(String, String, String, (TerminalSurfaceView) -> Void)] = [
            ("terminal.clear", "Clear Scrollback", "cmd+k", { $0.clearScrollback() }),
            ("terminal.zoomIn", "Zoom In", "cmd+=", { Self.zoom($0, by: 1) }),
            ("terminal.zoomOut", "Zoom Out", "cmd+-", { Self.zoom($0, by: -1) }),
        ]
        for (id, title, shortcut, perform) in actions {
            layout.shortcuts.register(
                ShortcutAction(id: id, title: title, scope: .terminal, defaultShortcut: shortcut) { [weak self] in
                    guard let self, let active = layout.model.active.active?.id, let surface = surfaces[active]
                    else { return }
                    perform(surface)
                })
        }
    }

    private static func zoom(_ surface: TerminalSurfaceView, by step: CGFloat) {
        let size = min(max(surface.font.pointSize + step, 8), 32)
        surface.font = NSFont(descriptor: surface.font.fontDescriptor, size: size) ?? surface.font
    }
}

// MARK: - SwiftTerm callbacks (delivered on the main queue by `LocalProcess`)

extension TerminalService: @preconcurrency LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // terminal R15: SwiftTerm already propagated the window size to the process.
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        guard let id = surfaces.first(where: { $0.value === source })?.key else { return }
        tabs[id]?.didSetTitle(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // terminal R4: no shell integration, the folder is the one of the launch.
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if let id = closing.first(where: { $0.value === source })?.key {
            closing[id] = nil
            return
        }
        guard let id = surfaces.first(where: { $0.value === source })?.key, let tab = tabs[id] else { return }
        let exit = TerminalExit(waitStatus: exitCode)
        tab.didExit(exit, isActive: isActive(id))
        syncBadge(id, tab)
        publish(.exited(id, exit))
    }
}
