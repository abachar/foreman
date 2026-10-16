import AppKit
import Foundation
import FuzzyMatch
import Observation
import SwiftUI
import os

/// Entry point of `run`: the commands of the config, one terminal session per command shown as a
/// sub-tab of the Run panel, the launch and relaunch logic (run R4, R7–R10, R12, R13; the Run
/// panel since 2026-10-16, M21 21.5).
@Observable
@MainActor
final class RunFeature {
    /// run R13 (amended 2026-10-16): the `run` section of `state.json` — the sub-tabs, in their
    /// order, and the one shown.
    nonisolated struct State: Codable, Equatable, Sendable {
        var commands: [String]
        var selected: String?
    }

    /// run R10: what a tab shows, derived from the terminal state.
    nonisolated enum RunState: Equatable, Sendable {
        case idle
        case running
        case succeeded
        /// `nil` when a signal ended the process.
        case failed(Int32?)

        init(_ state: TerminalState) {
            switch state {
            case .idle: self = .idle
            case .running: self = .running
            case .exited(.code(0)): self = .succeeded
            case .exited(.code(let code)): self = .failed(code)
            case .exited(.signal): self = .failed(nil)
            }
        }
    }

    /// run R7: what launching a command does to its session.
    nonisolated enum LaunchAction: Equatable, Sendable {
        case spawn
        case relaunch(TabID)
        /// `SIGINT` now, `relaunch` once `exited` arrives (R9).
        case stopThenRelaunch(TabID)
    }

    /// run R9: how long a stopped process may take to exit before the relaunch is given up.
    static let relaunchGrace: Duration = .seconds(10)
    /// run R9: a second `cmd+.` within this window escalates to `SIGTERM`.
    nonisolated static let stopEscalation: Duration = .seconds(2)
    static let toolbarID = "run.toolbar"
    /// run (panel, 2026-10-16): the bottom slot's Run tab.
    static let panelID: PanelID = "run.output"

    /// run R6b: one line of the ▶ Run menu, before it becomes a `ToolbarMenuEntry`.
    nonisolated struct MenuRow: Equatable, Sendable {
        let id: String
        let title: String
        let subtitle: String
        let badge: ToolbarBadge
        let isEnabled: Bool
    }

    private let layout: LayoutManager
    private let workspace: Workspace
    private let terminal: TerminalService
    private let palette: Palette
    private let theme: ThemeService
    private(set) var commands: [RunCommand] = []
    /// run R14, R15: the two sources merged into `commands`.
    private var declared: [RunCommand] = []
    private var detected: [RunCommand] = []
    private var detection: Task<Void, Never>?
    private var manifestWatch: Task<Void, Never>?
    /// run R5: the ids launched in this window, last first (decision 2026-08-27: not persisted).
    private(set) var recents: [String] = []
    /// run R7, R13 (amended 2026-10-16): the terminal session of each command, a sub-tab of the
    /// Run panel, reused by every launch; in the order they were opened.
    private(set) var sessions: [String: TabID] = [:]
    private(set) var sessionOrder: [String] = []
    /// The sub-tab shown in the Run panel.
    private(set) var selected: String?
    /// run R10 (amended 2026-10-17): how the last command to end ended, for the Run tab.
    private(set) var lastEnded: RunState?
    /// run R13: sub-tabs read from `state.json`, waiting for their command to be known.
    private var pendingRestore: State?
    private var registeredShortcuts: Set<String> = []
    private var isShown = false
    /// run R9: tabs waiting for `exited` to relaunch, with the task that gives up after the grace.
    private var pendingRelaunches: [TabID: Task<Void, Never>] = [:]
    /// run R9: when `cmd+.` last hit each tab.
    private var lastStops: [TabID: ContinuousClock.Instant] = [:]
    private var configWatch: Task<Void, Never>?
    private var eventsWatch: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "run")

    init(layout: LayoutManager, workspace: Workspace, terminal: TerminalService, palette: Palette, theme: ThemeService)
    {
        self.layout = layout
        self.workspace = workspace
        self.terminal = terminal
        self.palette = palette
        self.theme = theme
        pendingRestore = try? workspace.state.section("run", as: State.self)
        registerStop()
        apply(workspace.config)
        configWatch = Task { [weak self, workspace] in
            for await config in workspace.configChanges() {
                guard let self else { return }
                apply(config)
            }
        }
        eventsWatch = Task { [weak self, terminal] in
            for await event in terminal.events() {
                guard let self else { return }
                handle(event)
            }
        }
        // run R16: a manifest at a repo root changed.
        manifestWatch = Task { [weak self, workspace] in
            for await batch in await workspace.fsWatch.changes(under: workspace.root) {
                guard let self else { return }
                if batch.contains(where: { RunCatalog.manifests.contains($0.lastPathComponent) }) {
                    redetect()
                }
            }
        }
    }

    isolated deinit {
        configWatch?.cancel()
        eventsWatch?.cancel()
        detection?.cancel()
        manifestWatch?.cancel()
        for task in pendingRelaunches.values {
            task.cancel()
        }
    }

    // MARK: - Config (run R1–R4)

    private func apply(_ config: WorkspaceConfig) {
        let parsed: RunCatalog.Parsed
        do {
            parsed = RunCatalog.parse(try config.section("commands", as: RunCatalog.Section.self), root: workspace.root)
        } catch {
            logger.error("commands section ignored: \(error.localizedDescription, privacy: .public)")
            parsed = RunCatalog.parse(nil, root: workspace.root)
        }
        for warning in parsed.warnings {
            logger.warning("\(warning, privacy: .public)")
        }
        declared = parsed.commands
        publish()
        redetect()
    }

    /// run R14, R16: the manifests read off the main actor, then merged (R15).
    private func redetect() {
        detection?.cancel()
        let root = workspace.root
        let repos = workspace.config.repos
        detection = Task { [weak self] in
            let found = await Self.detect(root: root, repos: repos)
            guard !Task.isCancelled, let self else { return }
            detected = found
            publish()
        }
    }

    @concurrent
    private static func detect(root: URL, repos: [URL]) async -> [RunCommand] {
        RunCatalog.detect(root: root, repos: repos)
    }

    private func publish() {
        commands = RunCatalog.merge(declared: declared, detected: detected)
        for command in commands {
            register(command.id)
        }
        show(!commands.isEmpty)
        restoreSessions()
    }

    /// run R6b (2026-08-29), layout R36: the button and the palette exist only with a command.
    private func show(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        if shown {
            registerPalette()
            registerToolbar()
            registerPanel()
        } else {
            layout.shortcuts.unregister("run.palette")
            layout.removeToolbarItem(Self.toolbarID)
            layout.unregister(panel: Self.panelID)
        }
    }

    /// run R11: the shortcut of a command, for the whole window, outliving the command.
    ///
    /// It survives the command's removal from the config (decision 2026-08-27). No center tab kind
    /// any more (2026-10-16): a command runs in a sub-tab of the Run panel.
    private func register(_ id: String) {
        let kind = Self.kind(of: id)
        guard registeredShortcuts.insert(kind).inserted else { return }
        layout.shortcuts.register(
            ShortcutAction(id: kind, title: id, defaultShortcut: nil) { [weak self] in self?.launch(id) })
    }

    func command(_ id: String) -> RunCommand? {
        commands.first { $0.id == id }
    }

    nonisolated static func kind(of commandID: String) -> String {
        "run.\(commandID)"
    }

    // MARK: - Launching (run R7, R9)

    /// run R7 (amended 2026-10-16): the command's session is reused (stopped first when running).
    nonisolated static func launchAction(session: TabID?, state: TerminalState?) -> LaunchAction {
        guard let session, let state else { return .spawn }
        if case .running = state { return .stopThenRelaunch(session) }
        return .relaunch(session)
    }

    /// run R7: the session of the command, shown in the Run panel; `nil` when the command is not
    /// launchable (R2) or unknown.
    @discardableResult
    func launch(_ id: String) -> TabID? {
        guard let command = command(id), command.problem == nil else {
            logger.warning("run.\(id, privacy: .public) not launched: unknown or greyed")
            return nil
        }
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        let session: TabID
        switch Self.launchAction(session: sessions[id], state: sessions[id].flatMap { terminal.tab($0)?.state }) {
        case .spawn:
            session = start(command)
        case .relaunch(let tab):
            // Refused only for a missing folder; the session's banner says so.
            try? terminal.relaunch(tab)
            session = tab
        case .stopThenRelaunch(let tab):
            stopThenRelaunch(tab)
            session = tab
        }
        // run (panel, 2026-10-16): launching shows the panel on the command's sub-tab.
        select(id)
        layout.panels.show(Self.panelID)
        return session
    }

    private func start(_ command: RunCommand) -> TabID {
        let session = terminal.start(
            command: command.command, cwd: command.cwd, env: command.env, kind: Self.kind(of: command.id),
            title: command.id)
        adopt(session, commandID: command.id)
        return session
    }

    private func adopt(_ session: TabID, commandID: String) {
        sessions[commandID] = session
        if !sessionOrder.contains(commandID) {
            sessionOrder.append(commandID)
        }
        persist()
    }

    /// The sub-tab shown in the Run panel.
    func select(_ id: String) {
        guard sessions[id] != nil, selected != id else { return }
        selected = id
        persist()
    }

    /// run R12 (amended 2026-10-16): closing a sub-tab asks while its process runs, then stops it.
    func close(_ id: String) {
        guard let session = sessions[id] else { return }
        Task { [weak self] in
            guard let self, await terminal.confirmClose(session) else { return }
            terminal.closed(session)
            pendingRelaunches.removeValue(forKey: session)?.cancel()
            lastStops[session] = nil
            sessions[id] = nil
            sessionOrder.removeAll { $0 == id }
            if selected == id {
                selected = sessionOrder.last
            }
            persist()
        }
    }

    /// run R13 (amended 2026-10-16): the sub-tabs of the last session come back idle, in their
    /// folder, with today's command; nothing is relaunched.
    private func restoreSessions() {
        guard let state = pendingRestore else { return }
        let split = Self.restorable(state, known: Set(commands.map(\.id)), open: Set(sessions.keys))
        for id in split.now {
            guard let command = command(id) else { continue }
            let session = TabID()
            _ = terminal.restore(
                session, kind: Self.kind(of: id), title: id, command: command.command, cwd: command.cwd,
                env: command.env)
            adopt(session, commandID: id)
        }
        if let selected = state.selected, sessions[selected] != nil {
            self.selected = selected
        } else if selected == nil {
            selected = sessionOrder.first
        }
        pendingRestore = split.later
    }

    /// run R13: which persisted sub-tabs come back now — their command is known and not open yet —
    /// and which wait, detection (R14) possibly bringing their command later.
    nonisolated static func restorable(
        _ state: State, known: Set<String>, open: Set<String>
    ) -> (
        now: [String], later: State?
    ) {
        let now = state.commands.filter { known.contains($0) && !open.contains($0) }
        let later = state.commands.filter { !known.contains($0) && !open.contains($0) }
        return (now, later.isEmpty ? nil : State(commands: later, selected: state.selected))
    }

    private func persist() {
        workspace.setState("run", to: State(commands: sessionOrder, selected: selected))
    }

    /// run R9: `SIGINT`, then `relaunch` on `exited`; given up, and logged, after the grace period.
    private func stopThenRelaunch(_ tab: TabID) {
        guard pendingRelaunches[tab] == nil else { return }
        try? terminal.signal(SIGINT, to: tab)
        pendingRelaunches[tab] = Task { [weak self] in
            try? await Task.sleep(for: Self.relaunchGrace)
            guard let self, !Task.isCancelled else { return }
            pendingRelaunches[tab] = nil
            logger.warning("run tab still running after SIGINT, not relaunched")
        }
    }

    // MARK: - Panel (run, 2026-10-16)

    /// The bottom slot's third tab: a sub-tab per command run, the output of the one shown.
    private func registerPanel() {
        let theme = theme
        layout.register(
            panel: PanelDescriptor(
                id: Self.panelID, title: "Run", side: .bottom, icon: "play", order: 2,
                badge: { [weak self] in self?.panelBadge ?? .none },
                makeView: { [weak self] in
                    guard let self else { return AnyView(EmptyView()) }
                    return AnyView(
                        RunPanelView(run: self, terminal: terminal, panels: layout.panels, theme: theme))
                }))
    }

    /// run R10 (amended 2026-10-17): the Run tab's mark, from the sessions.
    private var panelBadge: ToolbarBadge {
        Self.tabMark(isRunning: sessions.values.contains { terminal.tab($0)?.isRunning == true }, lastEnded: lastEnded)
    }

    /// run R10 (amended 2026-10-17): an orange dot while a command runs, else the state of the
    /// last one to end — ✗ in red, ✓ in green — kept like the Run widget's icon (R6b).
    nonisolated static func tabMark(isRunning: Bool, lastEnded: RunState?) -> ToolbarBadge {
        if isRunning {
            return .dot(.orange)
        }
        switch lastEnded {
        case .failed: return .symbol("xmark", .red)
        case .succeeded: return .symbol("checkmark", .green)
        case .idle, .running, nil: return .none
        }
    }

    /// run R9 from the panel's ■ and ↻: the sub-tab shown.
    func restartSelected() {
        guard let selected else { return }
        launch(selected)
    }

    func clearSelected() {
        guard let selected, let session = sessions[selected] else { return }
        terminal.clearScrollback(session)
    }

    // MARK: - Palette (run R5, R6)

    private func registerPalette() {
        layout.shortcuts.register(
            ShortcutAction(id: "run.palette", title: "Run Command", defaultShortcut: "cmd+r") { [weak self] in
                self?.showPalette()
            })
    }

    /// `cmd+r`: the shared palette over the window (run R5).
    private func showPalette() {
        guard let window = NSApp.keyWindow else { return }
        let source = PaletteSource(
            placeholder: "Run command…",
            results: { [weak self] query in
                guard let self else { return PaletteSource.Results(items: []) }
                return PaletteSource.Results(
                    items: Self.items(commands, recents: recents, query: query),
                    notice: commands.isEmpty ? "No commands in .foreman/config.json" : nil)
            },
            // run R6 (amended 2026-10-16): one session per command, `cmd+enter` launches it too.
            select: { [weak self] item, _ in self?.launch(item.id) },
            secondary: { [weak self] item in
                // run R6: opt+enter copies the command text.
                guard let command = self?.command(item.id) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command.command, forType: .string)
            })
        palette.present(source, over: window)
    }

    /// run R5: recents first then the catalog order, or the fuzzy ranking on `repo name`.
    ///
    /// A greyed command shows its reason instead of its text.
    nonisolated static func items(_ commands: [RunCommand], recents: [String], query: String) -> [PaletteItem] {
        let ordered: [RunCommand]
        if query.isEmpty {
            let recent = recents.compactMap { id in commands.first { $0.id == id } }
            ordered = recent + commands.filter { !recents.contains($0.id) }
        } else {
            let byKey = Dictionary(commands.map { ("\($0.repo) \($0.name)", $0) }) { first, _ in first }
            let matches = FuzzyMatcher(config: .smithWaterman)
                .topMatches(byKey.keys, against: query, limit: Palette.limit)
            ordered = matches.compactMap { byKey[$0.candidate] }
        }
        return ordered.map { command in
            PaletteItem(
                id: command.id, title: PaletteItem.highlighted(command.title, matching: query),
                subtitle: command.subtitle)
        }
    }

    // MARK: - Toolbar (run R6b)

    /// run R6b (amended 2026-10-16, M21 21.3): the Run widget — the current command and its last
    /// state, ▶ (↻ while it runs) and ■; the command opens the menu of every command.
    private func registerToolbar() {
        let theme = theme
        layout.register(
            toolbarItem: ToolbarItemDescriptor(
                id: Self.toolbarID, title: "Run", icon: "play.fill", placement: .trailing,
                kind: .widget(
                    view: { [weak self] openMenu in
                        guard let self else { return AnyView(EmptyView()) }
                        return AnyView(RunWidget(run: self, theme: theme, openMenu: openMenu))
                    },
                    menu: { [weak self] in ToolbarMenu(entries: self?.widgetMenuEntries() ?? []) })))
    }

    /// run R6b (amended 2026-10-16): the command the widget launches — the last one launched in
    /// this window, else the first of the catalog.
    var current: RunCommand? {
        recents.lazy.compactMap { id in self.commands.first { $0.id == id && $0.problem == nil } }.first
            ?? commands.first { $0.problem == nil }
    }

    /// The state of a command's primary tab; `nil` when it never ran in this window.
    func state(ofCommand id: String) -> RunState? {
        sessions[id].flatMap(state(of:))
    }

    /// run R9, from the widget's ■: the command's primary tab, escalating like `cmd+.` does.
    func stop(_ id: String) {
        guard let tab = sessions[id] else { return }
        stop(tab: tab)
    }

    /// The widget's menu: the commands with their state, then *Run Command…* and *Stop*.
    private func widgetMenuEntries() -> [ToolbarMenuEntry] {
        var entries = menuEntries()
        entries.append(
            ToolbarMenuEntry(
                id: "run.palette", title: "Run Command…", shortcut: layout.shortcuts.shortcut(for: "run.palette"),
                startsSection: true
            ) { [weak self] in self?.showPalette() })
        if let current, state(ofCommand: current.id) == .running {
            entries.append(
                ToolbarMenuEntry(
                    id: "run.stop", title: "Stop \(current.id)", shortcut: layout.shortcuts.shortcut(for: "run.stop")
                ) { [weak self] in self?.stop(current.id) })
        }
        return entries
    }

    /// run R6b: every command with its state.
    nonisolated static func menuRows(_ commands: [RunCommand], badge: (String) -> ToolbarBadge) -> [MenuRow] {
        var rows: [MenuRow] = []
        for command in commands {
            // run R15: the detected ones after the declared ones, under one heading.
            if command.source != nil, !rows.contains(where: { $0.id == "run.detected" }) {
                rows.append(
                    MenuRow(
                        id: "run.detected", title: "Detected", subtitle: "from the project's manifests", badge: .none,
                        isEnabled: false))
            }
            rows.append(
                MenuRow(
                    id: kind(of: command.id), title: command.title, subtitle: command.subtitle,
                    badge: command.problem == nil ? badge(command.id) : .none, isEnabled: command.problem == nil))
        }
        return rows
    }

    private func menuEntries() -> [ToolbarMenuEntry] {
        Self.menuRows(commands) { id in
            // run R6b (amended 2026-10-16): the last state stays in the menu, there is no tab to visit.
            guard let tab = sessions[id], let terminalTab = terminal.tab(tab) else { return .none }
            return Self.badge(RunState(terminalTab.state), marked: true)
        }
        .map { row in
            // layout R37: a command the user gave a shortcut says so in the menu (`config.shortcuts`).
            ToolbarMenuEntry(
                id: row.id, title: row.title, subtitle: row.subtitle, badge: row.badge,
                shortcut: layout.shortcuts.shortcut(for: row.id)
            ) { [weak self] in
                guard row.isEnabled, let id = self?.commands.first(where: { Self.kind(of: $0.id) == row.id })?.id
                else { return }
                self?.launch(id)
            }
        }
    }

    // MARK: - Stop (run R9)

    private func registerStop() {
        layout.shortcuts.register(
            ShortcutAction(id: "run.stop", title: "Stop Command", scope: .panel, defaultShortcut: "cmd+.") {
                [weak self] in self?.stopShown()
            })
    }

    /// run R9: `SIGINT`, or `SIGTERM` when the previous stop was less than two seconds ago.
    nonisolated static func stopSignal(lastStop: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Int32 {
        guard let lastStop, now - lastStop < stopEscalation else { return SIGINT }
        return SIGTERM
    }

    /// run R9 (amended 2026-10-16): the sub-tab shown in the Run panel, while a panel has the
    /// focus (scope `panel`) and the Run panel is shown; anywhere else `cmd+.` is left to the content
    /// — the query tab cancels with it — and does nothing on an agent (decision 2026-08-27).
    private func stopShown() {
        guard layout.panels.isVisible(Self.panelID), let selected, let session = sessions[selected] else { return }
        stop(tab: session)
    }

    private func stop(tab id: TabID) {
        let now = ContinuousClock.now
        let signal = Self.stopSignal(lastStop: lastStops[id], now: now)
        lastStops[id] = now
        try? terminal.signal(signal, to: id)
    }

    // MARK: - State and badges (run R10)

    func state(of tab: TabID) -> RunState? {
        terminal.tab(tab).map { RunState($0.state) }
    }

    /// run R10: blue while running; green or red once ended, until the tab is shown.
    nonisolated static func badge(_ state: RunState, marked: Bool) -> ToolbarBadge {
        switch state {
        case .idle: return .none
        case .running: return .dot(.blue)
        case .succeeded: return marked ? .dot(.green) : .none
        case .failed: return marked ? .dot(.red) : .none
        }
    }

    private func handle(_ event: TerminalEvent) {
        let id: TabID
        switch event {
        case .started(let tab, _), .exited(let tab, _), .bell(let tab), .activated(let tab), .closed(let tab):
            id = tab
        }
        guard sessions.values.contains(id) else { return }
        if case .exited(_, let exit) = event, pendingRelaunches[id] == nil {
            lastEnded = RunState(.exited(exit))
        }
        if case .exited = event, let pending = pendingRelaunches.removeValue(forKey: id) {
            pending.cancel()
            try? terminal.relaunch(id)
        }
    }
}
