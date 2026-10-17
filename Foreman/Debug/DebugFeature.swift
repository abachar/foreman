import AppKit
import Foundation
import JSONRPC
import LanguageServerProtocol
import SwiftUI
import os

/// The owner of a debug session and of the breakpoints (debug R3–R5, R9–R11).
///
/// M27 27.2: breakpoints in the gutter, an attach started from the Run menu, the palette or
/// `ctrl+cmd+r`, and the paused line. 27.3: the Debug panel (`DebugPanelModel`, `DebugPanelView`) and
/// the stepping shortcuts.
///
/// Nothing runs before `start` (R10): no adapter, no port, no work while the window only sits there.
@MainActor
final class DebugFeature {
    static let startActionID = "debug.start"
    static let toggleActionID = "debug.toggleBreakpoint"
    /// debug R6: the bottom slot's Debug tab.
    static let panelID: PanelID = "debug.panel"

    private let workspace: Workspace
    let run: RunFeature
    private let editor: EditorFeature
    let layout: LayoutManager
    let theme: ThemeService
    /// debug R6, R10: what the panel shows; an empty value until a session starts.
    let model = DebugPanelModel()
    var isPanelRegistered = false
    var didShowPanel = false
    private var store: BreakpointStore
    var mark = PausedMark()
    private var areShortcutsRegistered = false
    private var commandID: String?
    let logger = Logger(subsystem: "dev.crafters.foreman", category: "debug")
    private(set) var catalog = DebugCatalog.empty
    private var configWatch: Task<Void, Never>?
    var session: DAPSession?
    private var request: DebugCommand.Request?
    /// The extension of the running session's adapter: the language server that serves a library frame.
    private var adapterKey: String?
    /// Whether the running session talks to a language server's adapter (debug R1, R11).
    private var viaServer = false
    private var listening: Task<Void, Never>?

    init(workspace: Workspace, run: RunFeature, editor: EditorFeature, layout: LayoutManager, theme: ThemeService) {
        self.workspace = workspace
        self.run = run
        self.editor = editor
        self.layout = layout
        self.theme = theme
        store = BreakpointStore(state: (try? workspace.state.section("debug", as: BreakpointStore.State.self)) ?? nil)
        // debug R3, R9: Run offers the 🐞 entries and tells when a sub-tab closes; the editor tells
        // when a tab is bound to its view and when its text is read.
        run.canDebug = { [weak self] in self?.canDebug($0) ?? false }
        run.startDebug = { [weak self] id in Task { await self?.start(commandID: id) } }
        run.subTabClosed = { [weak self] id in Task { await self?.subTabClosed(id) } }
        editor.tabBound = { [weak self] in self?.bind($0) }
        editor.tabLoaded = { [weak self] in self?.loaded($0) }
        run.commandsChanged = { [weak self] in self?.updatePanel() }
        // debug R7: the stepping keys are bound while the session is paused.
        model.onStateChange = { [weak self] in self?.updateStepShortcuts() }
        apply(workspace.config)
        configWatch = Task { [weak self, workspace] in
            for await config in workspace.configChanges() {
                guard let self else { return }
                apply(config)
            }
        }
    }

    isolated deinit {
        configWatch?.cancel()
        listening?.cancel()
    }

    // MARK: - Config (debug R1)

    private func apply(_ config: WorkspaceConfig) {
        do {
            catalog = try config.section("debug", as: DebugCatalog.self) ?? .empty
        } catch {
            logger.error("debug section ignored: \(error.localizedDescription, privacy: .public)")
            catalog = .empty
        }
        for warning in catalog.warnings {
            logger.warning("\(warning, privacy: .public)")
        }
        updateShortcuts()
        updatePanel()
        refreshTabs()
    }

    /// Without a section there is no shortcut, no 🐞 and no dot (layout R36).
    private var isEnabled: Bool {
        !catalog.adapters.isEmpty
    }

    /// debug R3, R7: `ctrl+cmd+r` and `cmd+\` exist while an adapter is declared.
    private func updateShortcuts() {
        guard isEnabled != areShortcutsRegistered else { return }
        areShortcutsRegistered = isEnabled
        guard isEnabled else {
            layout.shortcuts.unregister(Self.startActionID)
            layout.shortcuts.unregister(Self.toggleActionID)
            return
        }
        layout.shortcuts.register(
            ShortcutAction(id: Self.startActionID, title: "Debug", defaultShortcut: "ctrl+cmd+r") { [weak self] in
                self?.startCurrent()
            })
        layout.shortcuts.register(
            ShortcutAction(
                id: Self.toggleActionID, title: "Toggle Breakpoint", scope: .tab(kind: EditorFeature.tabKind),
                defaultShortcut: "cmd+\\"
            ) { [weak self] in self?.toggleAtCaret() })
    }

    // MARK: - Breakpoints (debug R4)

    /// debug R4: only a file under the root takes a breakpoint — not a library tab, not a file outside.
    private func key(of tab: EditorTab) -> String? {
        isEnabled ? BreakpointStore.key(for: tab.url, root: workspace.root) : nil
    }

    /// A tab met its view: it gets its dots, its paused line and the hooks that change them.
    private func bind(_ tab: EditorTab) {
        tab.onToggleBreakpoint = { [weak self, weak tab] line in
            guard let self, let tab, let key = key(of: tab) else { return }
            store.toggle(line, in: key)
            changed(key)
        }
        tab.onLinesEdited = { [weak self, weak tab] edit in
            guard let self, let tab, let key = key(of: tab), store.apply(edit, in: key) else { return }
            changed(key)
        }
        refresh(tab)
    }

    /// debug R4: restoration — a line past the end of the file is dropped once the text is known.
    private func loaded(_ tab: EditorTab) {
        guard let key = key(of: tab),
            store.drop(pastLine: BreakpointStore.lineCount(of: tab.currentText), in: key)
        else { return }
        changed(key)
    }

    private func toggleAtCaret() {
        guard let tab = editor.activeTab, let textView = tab.textView, let key = key(of: tab) else { return }
        let line = TextEditing.position(at: textView.selectedRange().location, in: textView.string as NSString).line
        store.toggle(line, in: key)
        changed(key)
    }

    /// The set of a file changed: saved, drawn, and sent while a session runs.
    private func changed(_ key: String) {
        workspace.setState("debug", to: store.state)
        refreshTabs()
        guard let session else { return }
        let file = store.file(key, root: workspace.root)
        Task { [weak self, logger] in
            do {
                let response = try await session.setBreakpoints(file)
                self?.recorded(response, for: file, key: key, in: session)
            } catch {
                logger.error("setBreakpoints failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func recorded(
        _ response: DAPSetBreakpointsResponse, for file: DAPSession.FileBreakpoints, key: String, in session: DAPSession
    ) {
        guard self.session === session else { return }
        store.record(response, requested: file.lines, in: key)
        refreshTabs()
    }

    /// The dots and the paused line of every tab, from the store and the mark.
    func refreshTabs() {
        for tab in editor.openTabs {
            refresh(tab)
        }
    }

    private func refresh(_ tab: EditorTab) {
        let dots = key(of: tab).map { store.marks(in: $0) } ?? [:]
        if tab.breakpoints != dots {
            tab.breakpoints = dots
        }
        let paused = isEnabled ? mark.line(in: tab.url) : nil
        if tab.pausedLine != paused {
            tab.pausedLine = paused
        }
    }

    // MARK: - Session (debug R2, R3, R9, R11)

    /// debug R3: the command is offered as Debug when its adapter is declared; a `debug`-only command
    /// is greyed for the ▶ (nothing to run) and not for this.
    private func canDebug(_ command: RunCommand) -> Bool {
        guard let debug = command.debug, catalog.adapters[debug.adapter] != nil else { return false }
        return command.problem == nil || command.command.isEmpty
    }

    /// debug R3: `ctrl+cmd+r` — the Run widget's current command.
    private func startCurrent() {
        guard let current = run.current, canDebug(current) else {
            logger.warning("debug.start: the Run widget's command has no `debug` object")
            return
        }
        Task { await start(commandID: current.id) }
    }

    /// debug R9: the sub-tab of the session's command closed.
    private func subTabClosed(_ id: String) async {
        if commandID == id {
            await stop()
        }
    }

    /// Starts the command's `debug` session, ending the one that runs.
    ///
    /// An attach runs the command as ▶ does, then connects at once: the adapter does the waiting
    /// (R3). Every failure is shown with the adapter's own words on the command's sub-tab and ends
    /// the session; the program is left alone (R11).
    func start(commandID: String) async {
        await stop()
        guard let command = run.command(commandID), let debug = command.debug else {
            logger.error("debug \(commandID, privacy: .public): unknown command, or no `debug` object")
            return
        }
        guard let adapter = catalog.adapters[debug.adapter] else {
            logger.error(
                "debug \(commandID, privacy: .public): `debug.\(debug.adapter, privacy: .public)` is not declared")
            return
        }
        adapterKey = debug.adapter
        if debug.request == .attach, !command.command.isEmpty {
            run.launch(commandID)
        }
        let session: DAPSession
        do {
            session = try await connect(adapter, extensionKey: debug.adapter)
        } catch {
            fail(commandID, String(describing: error))
            return
        }
        viaServer = adapter.isServer
        self.session = session
        self.commandID = commandID
        request = debug.request
        didShowPanel = false
        model.begin(.connecting(debug.request, arguments: debug.arguments)) { [session] command, arguments in
            try await session.send(command, arguments)
        }
        listen(to: session)
        let keys = store.lines.keys.sorted()
        let files = keys.map { store.file($0, root: workspace.root) }
        do {
            let answers = try await session.start(debug.request, arguments: debug.arguments, breakpoints: files)
            guard self.session === session else { return }
            for (key, file) in zip(keys, files) {
                if let answer = answers[file.path] {
                    store.record(answer, requested: file.lines, in: key)
                }
            }
            refreshTabs()
            model.started()
            logger.debug("debug \(commandID, privacy: .public) started")
        } catch {
            let message = Self.banner(for: error, standardError: await session.lastError)
            await stop()
            fail(commandID, message)
        }
    }

    /// debug R1: the channel to the adapter.
    ///
    /// A process on stdio, or the TCP port the language server answers to its command (the `server`
    /// form). Throws R11's sentence.
    private func connect(_ adapter: DebugCatalog.Adapter, extensionKey: String) async throws -> DAPSession {
        switch adapter {
        case .command(let text):
            let environment = await workspace.loginEnvironment()
            guard FormatterCatalog.isBinaryAvailable(text, inPath: environment["PATH"]) else {
                throw DAPSession.Failure.unreachable("`\(FormatterCatalog.binary(of: text))` is not in the PATH")
            }
            return try DAPSession.stdio(
                command: text, cwd: workspace.root, environment: environment, adapterID: extensionKey,
                timeout: catalog.timeout)
        case .server(let id):
            let answer = await editor.lsp.executeCommand(id, extensionKey: extensionKey)
            guard let port = Self.port(of: answer) else {
                let declaration = editor.lsp.declaration(forExtension: extensionKey)
                throw DAPSession.Failure.unreachable(
                    Self.noPort(
                        command: id, extensionKey: extensionKey, answer: answer, declared: declaration.declared,
                        failure: declaration.failure))
            }
            return try await DAPSession.tcp(port: port, adapterID: extensionKey, timeout: catalog.timeout)
        }
    }

    /// debug R1: a port from the language server's answer — a number, or a string holding one.
    nonisolated static func port(of answer: LSPAny?) -> Int? {
        var value: Int?
        if case .number(let number)? = answer, number == number.rounded(), abs(number) < 1_000_000 {
            value = Int(number)
        } else if case .string(let text)? = answer {
            value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return value.flatMap { (1...65535).contains($0) ? $0 : nil }
    }

    /// debug R11: why a `server` adapter has no port, in the language server's own words when it
    /// failed to start.
    nonisolated static func noPort(
        command: String, extensionKey: String, answer: LSPAny?, declared: Bool, failure: String?
    ) -> String {
        if !declared {
            return "`debug.\(extensionKey)` needs a language server: `lsp.\(extensionKey)` is not declared"
        }
        if let failure {
            return failure
        }
        guard let answer, answer != .null else {
            return "\(command) answered no port: no answer (is the debug bundle loaded?)"
        }
        let text = (try? String(data: JSONEncoder().encode(answer), encoding: .utf8)) ?? String(describing: answer)
        return "\(command) answered no port: \(text)"
    }

    /// debug R11: the session of a `server` adapter lives in the language server's process, so the
    /// channel closing is its restart or stop.
    nonisolated static func serverEnded(extensionKey: String) -> String {
        "the `\(extensionKey)` language server stopped or restarted: the session ended"
    }

    /// debug R11: the adapter's `message` when it sent one, else what happened and the last line it
    /// wrote on `stderr`.
    nonisolated static func banner(for error: any Error, standardError: String?) -> String {
        if case DAPSession.Failure.rejected(_, let message) = error {
            return message
        }
        let what = (error as? DAPSession.Failure)?.description ?? String(describing: error)
        return standardError.map { "\(what) \u{2014} \($0)" } ?? what
    }

    /// debug R11: one banner on the command's Run sub-tab; the active editor tab's when the command
    /// has none (a `launch` that runs nothing).
    private func fail(_ commandID: String, _ message: String) {
        logger.error("debug \(commandID, privacy: .public): \(message, privacy: .private)")
        let text = "Debug \(commandID): \(message)"
        model.fail(message)
        if !run.showBanner(text, for: commandID) {
            editor.activeTab?.message = text
        }
    }

    /// R9: `disconnect` — the program is terminated for a launch, left running for an attach.
    func stop() async {
        guard let session else { return }
        let terminate = request == .launch
        self.session = nil
        request = nil
        commandID = nil
        // debug R5: the mark goes with the session, the dots turn hollow.
        mark.clear()
        model.end()
        store.forgetVerification()
        refreshTabs()
        await session.stop(terminateDebuggee: terminate)
    }

    /// R9: the events, logged; `terminated` and `exited` end the session.
    ///
    /// A stream that finishes is the adapter's process dying.
    private func listen(to session: DAPSession) {
        listening = Task { [weak self, logger] in
            for await message in session.messages {
                switch (message.type, message.event ?? message.command) {
                case (.event, "stopped"?):
                    await self?.stopped(message, in: session)
                case (.event, "continued"?):
                    self?.handle(event: "continued")
                case (.event, "output"?):
                    if let output = try? message.decodedBody(DAPOutputEvent.self) {
                        self?.model.output(output)
                    }
                case (.event, "terminated"?), (.event, "exited"?):
                    logger.debug("\(message.event ?? "", privacy: .public)")
                    self?.handle(event: message.event ?? "")
                    await self?.ended(session)
                case (.request, let command?):
                    logger.debug("reverse request \(command, privacy: .public) refused (27.5)")
                    await session.respond(to: message, success: false, message: "not supported yet")
                default:
                    break
                }
            }
            await self?.ended(session, channelClosed: true)
        }
    }

    /// debug R5: `continued`, `terminated` and `exited` take the mark off.
    private func handle(event name: String) {
        mark.handle(event: name)
        model.handle(event: name)
        refreshTabs()
    }

    /// debug R5, R6: `threads`, then the stopping thread's frames (the panel's model); the top frame
    /// is shown, and its scopes asked in parallel.
    ///
    /// Without a `threadId` (`allThreadsStopped`) the first thread is the one. The caret stays where
    /// the user left it; the line is shown only when it is off screen.
    private func stopped(_ message: DAPMessage, in session: DAPSession) async {
        let event = try? message.decodedBody(DAPStoppedEvent.self)
        logger.debug("stopped thread \(event?.threadId ?? -1): \(event?.reason ?? "?", privacy: .public)")
        let frame: DAPStackFrame
        do {
            guard let top = try await model.stopped(threadID: event?.threadId) else {
                logger.error("stopped: the adapter lists no thread or frame")
                return
            }
            frame = top
        } catch {
            logger.error("stopped: \(String(describing: error), privacy: .public)")
            return
        }
        guard self.session === session else { return }
        // debug R6: the panel comes up with the first stop of a session, and not again once closed.
        if !didShowPanel, isPanelRegistered {
            didShowPanel = true
            layout.panels.show(Self.panelID)
        }
        Task { [model] in await model.loadScopes(of: frame.id) }
        await show(frame)
    }

    /// Opens the frame's source with the caret kept, and moves the paused line to it.
    func show(_ frame: DAPStackFrame) async {
        guard let session else { return }
        switch StoppedTarget.resolve(frame.source) {
        case .file(let url):
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                unmarked("`\(url.path(percentEncoded: false))` does not exist")
                return
            }
            editor.open(url, preview: true, line: frame.line, revealOnly: true)
            paused(at: url, line: frame.line)
        case .library(let uri):
            let opened = await editor.openLibrarySource(
                uri: uri, extensionKey: adapterKey ?? "", line: frame.line, revealOnly: true)
            guard self.session === session else { return }
            guard let opened else {
                unmarked("no source for `\(uri)`")
                return
            }
            paused(at: opened, line: frame.line)
        case .unavailable(let reason):
            unmarked(reason)
        }
    }

    private func paused(at url: URL, line: Int) {
        mark.stopped(at: PausedMark.Location(url: url.standardizedFileURL, line: line))
        refreshTabs()
    }

    /// debug R11: a stop whose source cannot be opened marks nothing and says so in the panel's state line.
    private func unmarked(_ reason: String) {
        logger.error("stopped: \(reason, privacy: .private)")
        model.notice = reason
        mark.clear()
        refreshTabs()
    }

    /// The session is over for good: only the current one resets the owner.
    ///
    /// A channel that closed under a `server` adapter is the language server's death (debug R11): no
    /// `terminated` came first, and the banner says whose it was.
    private func ended(_ finished: DAPSession, channelClosed: Bool = false) async {
        guard session === finished else { return }
        logger.debug("debug session ended")
        let lost = channelClosed && viaServer ? commandID : nil
        let key = adapterKey ?? ""
        await stop()
        if let lost {
            fail(lost, Self.serverEnded(extensionKey: key))
        }
    }
}
