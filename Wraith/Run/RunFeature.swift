import Foundation
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

    private let layout: LayoutManager
    private let workspace: Workspace
    private let terminal: TerminalService
    private(set) var commands: [RunCommand] = []
    /// run R7: the tab a command reuses, the first one opened or restored for it.
    private var primaryTabs: [String: TabID] = [:]
    private var commandOfTab: [TabID: String] = [:]
    private var registeredKinds: Set<String> = []
    /// run R9: tabs waiting for `exited` to relaunch, with the task that gives up after the grace.
    private var pendingRelaunches: [TabID: Task<Void, Never>] = [:]
    private var configWatch: Task<Void, Never>?
    private var eventsWatch: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "run")

    init(layout: LayoutManager, workspace: Workspace, terminal: TerminalService) {
        self.layout = layout
        self.workspace = workspace
        self.terminal = terminal
        apply(workspace.config)
        configWatch = Task { [weak self, workspace] in
            for await config in workspace.configChanges {
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
    }

    isolated deinit {
        configWatch?.cancel()
        eventsWatch?.cancel()
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
        commands = parsed.commands
        for command in commands {
            register(command.id)
        }
    }

    /// The tab kind of a command exists for the whole window, so its tabs restore (layout R28) and
    /// survive its removal from the config (run R4).
    private func register(_ id: String) {
        let kind = Self.kind(of: id)
        guard !registeredKinds.contains(kind) else { return }
        registeredKinds.insert(kind)
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
        guard let commandID = commandOfTab.removeValue(forKey: id) else { return }
        if primaryTabs[commandID] == id {
            primaryTabs[commandID] = commandOfTab.first { $0.value == commandID }?.key
        }
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
