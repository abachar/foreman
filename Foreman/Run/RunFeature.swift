import AppKit
import Foundation
import FuzzyMatch
import SwiftUI
import os

/// Entry point of `run`: one `run.<id>` tab kind per command of the config, the terminal surface
/// behind each tab, the launch and relaunch logic (run R4, R7–R10, R12, R13).
@MainActor
final class RunFeature {
    nonisolated struct Payload: Codable, Equatable, Sendable {
        let id: String
        /// config R10: relative to the root when inside it.
        let cwd: String
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

    /// run R7: what launching a command does to its tab.
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
    private(set) var commands: [RunCommand] = []
    /// run R14, R15: the two sources merged into `commands`.
    private var declared: [RunCommand] = []
    private var detected: [RunCommand] = []
    private var detection: Task<Void, Never>?
    private var manifestWatch: Task<Void, Never>?
    /// run R5: the ids launched in this window, last first (decision 2026-08-27: not persisted).
    private(set) var recents: [String] = []
    /// run R7: the tab a command reuses, the first one opened or restored for it.
    private var primaryTabs: [String: TabID] = [:]
    private var commandOfTab: [TabID: String] = [:]
    private var registeredKinds: Set<String> = []
    private var isShown = false
    /// run R9: tabs waiting for `exited` to relaunch, with the task that gives up after the grace.
    private var pendingRelaunches: [TabID: Task<Void, Never>] = [:]
    /// run R9: when `cmd+.` last hit each tab.
    private var lastStops: [TabID: ContinuousClock.Instant] = [:]
    /// run R6b: the tab whose failure the button reports, until it is shown.
    private var lastFailed: TabID?
    private var configWatch: Task<Void, Never>?
    private var eventsWatch: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "run")

    init(layout: LayoutManager, workspace: Workspace, terminal: TerminalService, palette: Palette) {
        self.layout = layout
        self.workspace = workspace
        self.terminal = terminal
        self.palette = palette
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
    }

    /// run R6b (2026-08-29), layout R36: the button and the palette exist only with a command.
    private func show(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        if shown {
            registerPalette()
            registerToolbar()
        } else {
            layout.shortcuts.unregister("run.palette")
            layout.removeToolbarItem(Self.toolbarID)
        }
    }

    /// The tab kind of a command exists for the whole window, so its tabs restore (layout R28) and
    /// survive its removal from the config (run R4).
    private func register(_ id: String) {
        let kind = Self.kind(of: id)
        guard !registeredKinds.contains(kind) else { return }
        registeredKinds.insert(kind)
        // run R11: no default; the shortcut outlives the command (decision 2026-08-27).
        layout.shortcuts.register(
            ShortcutAction(id: kind, title: id, defaultShortcut: nil) { [weak self] in self?.launch(id) })
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: kind, isTerminal: true,
                makeView: { [weak self] tab, payload in self?.view(tab, payload: payload, commandID: id) },
                serialize: { [weak self] tab in self?.serialize(tab, commandID: id) },
                confirmClose: { [weak self] tab in await self?.terminal.confirmClose(tab) ?? true },
                onClose: { [weak self] tab in self?.closed(tab) }))
    }

    func command(_ id: String) -> RunCommand? {
        commands.first { $0.id == id }
    }

    nonisolated static func kind(of commandID: String) -> String {
        "run.\(commandID)"
    }

    // MARK: - Launching (run R7, R9)

    /// run R7: the primary tab is reused (stopped first when running); `newTab` (R6) always spawns.
    nonisolated static func launchAction(primary: TabID?, state: TerminalState?, newTab: Bool) -> LaunchAction {
        guard !newTab, let primary, let state else { return .spawn }
        if case .running = state { return .stopThenRelaunch(primary) }
        return .relaunch(primary)
    }

    /// The tab of the command, or `nil` when it is not launchable (R2) or unknown.
    @discardableResult
    func launch(_ id: String, newTab: Bool = false) -> TabID? {
        guard let command = command(id), command.problem == nil else {
            logger.warning("run.\(id, privacy: .public) not launched: unknown or greyed")
            return nil
        }
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        let primary = primaryTabs[id].flatMap { layout.model.owner(of: $0) != nil ? $0 : nil }
        switch Self.launchAction(primary: primary, state: primary.flatMap { terminal.tab($0)?.state }, newTab: newTab)
        {
        case .spawn:
            return spawn(command, primary: primary == nil)
        case .relaunch(let tab):
            activate(tab)
            // Refused only for a missing folder; the tab's banner says so.
            try? terminal.relaunch(tab)
            return tab
        case .stopThenRelaunch(let tab):
            activate(tab)
            stopThenRelaunch(tab)
            return tab
        }
    }

    private func spawn(_ command: RunCommand, primary: Bool) -> TabID? {
        guard
            let tab = terminal.spawn(
                command: command.command, cwd: command.cwd, env: command.env, kind: Self.kind(of: command.id),
                title: command.id)
        else { return nil }
        commandOfTab[tab] = command.id
        if primary {
            primaryTabs[command.id] = tab
        }
        return tab
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

    private func activate(_ tab: TabID) {
        guard let owner = layout.model.owner(of: tab) else { return }
        layout.activate(tab, in: owner)
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
            select: { [weak self] item, newTab in self?.launch(item.id, newTab: newTab) },
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

    private func registerToolbar() {
        layout.register(
            toolbarItem: ToolbarItemDescriptor(
                id: Self.toolbarID, title: "Run", icon: "play.fill", placement: .trailing,
                kind: .menu(entries: { [weak self] in self?.menuEntries() ?? [] })))
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
            guard let tab = primaryTabs[id], let terminalTab = terminal.tab(tab) else { return .none }
            return Self.badge(RunState(terminalTab.state), marked: terminalTab.isMarked)
        }
        .map { row in
            ToolbarMenuEntry(id: row.id, title: row.title, subtitle: row.subtitle, badge: row.badge) { [weak self] in
                guard row.isEnabled, let id = self?.commands.first(where: { Self.kind(of: $0.id) == row.id })?.id
                else { return }
                self?.launch(id)
            }
        }
    }

    /// run R6b: blue while anything runs, red while the last failure has not been looked at.
    nonisolated static func toolbarBadge(anyRunning: Bool, hasUnseenFailure: Bool) -> ToolbarBadge {
        anyRunning ? .dot(.blue) : (hasUnseenFailure ? .dot(.red) : .none)
    }

    private func syncToolbarBadge() {
        let running = commandOfTab.keys.contains { terminal.tab($0)?.isRunning == true }
        layout.setBadge(Self.toolbarBadge(anyRunning: running, hasUnseenFailure: lastFailed != nil), on: Self.toolbarID)
    }

    // MARK: - Stop (run R9)

    private func registerStop() {
        layout.shortcuts.register(
            ShortcutAction(id: "run.stop", title: "Stop Command", scope: .terminal, defaultShortcut: "cmd+.") {
                [weak self] in self?.stopActiveTab()
            })
    }

    /// run R9: `SIGINT`, or `SIGTERM` when the previous stop was less than two seconds ago.
    nonisolated static func stopSignal(lastStop: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Int32 {
        guard let lastStop, now - lastStop < stopEscalation else { return SIGINT }
        return SIGTERM
    }

    /// run R9: only a `run.*` tab; `cmd+.` on an agent does nothing (decision 2026-08-27).
    private func stopActiveTab() {
        guard let id = layout.model.active.active?.id, commandOfTab[id] != nil else { return }
        let now = ContinuousClock.now
        let signal = Self.stopSignal(lastStop: lastStops[id], now: now)
        lastStops[id] = now
        try? terminal.signal(signal, to: id)
    }

    // MARK: - Tabs (run R12, R13, layout R28)

    private func view(_ id: TabID, payload: String, commandID: String) -> AnyView? {
        if let view = terminal.view(for: id) {
            adopt(id, commandID: commandID)
            return view
        }
        // run R13: restored idle in its folder, with today's command, never run by itself.
        guard let command = command(commandID), let data = payload.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        adopt(id, commandID: commandID)
        return terminal.restore(
            id, kind: Self.kind(of: commandID), title: commandID, command: command.command,
            cwd: Workspace.url(forPersistedPath: decoded.cwd, root: workspace.root), env: command.env)
    }

    private func adopt(_ id: TabID, commandID: String) {
        commandOfTab[id] = commandID
        if primaryTabs[commandID] == nil {
            primaryTabs[commandID] = id
        }
    }

    private func serialize(_ id: TabID, commandID: String) -> String? {
        guard let tab = terminal.tab(id) else { return nil }
        let payload = Payload(id: commandID, cwd: Workspace.persistedPath(for: tab.cwd, root: workspace.root))
        // A two-field Codable struct always encodes.
        return String(decoding: (try? JSONEncoder().encode(payload)) ?? Data(), as: UTF8.self)
    }

    private func closed(_ id: TabID) {
        terminal.closed(id)
        pendingRelaunches.removeValue(forKey: id)?.cancel()
        lastStops[id] = nil
        if lastFailed == id {
            lastFailed = nil
        }
        guard let commandID = commandOfTab.removeValue(forKey: id) else { return }
        if primaryTabs[commandID] == id {
            primaryTabs[commandID] = commandOfTab.first { $0.value == commandID }?.key
        }
        syncToolbarBadge()
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
        guard commandOfTab[id] != nil, let tab = terminal.tab(id) else { return }
        defer { syncToolbarBadge() }
        switch event {
        case .exited(_, let exit) where exit != .code(0):
            lastFailed = id
        case .activated where lastFailed == id:
            lastFailed = nil
        case .started, .exited, .bell, .activated, .closed:
            break
        }
        if case .exited = event, let pending = pendingRelaunches.removeValue(forKey: id) {
            pending.cancel()
            try? terminal.relaunch(id)
            return
        }
        // Published after the service's own badge (terminal R7), so this one is the one shown.
        layout.update(
            id, title: tab.title, isDirty: tab.isRunning, badge: Self.badge(RunState(tab.state), marked: tab.isMarked))
    }
}
