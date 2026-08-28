import AppKit
import Foundation
import SwiftUI
import os

/// Entry point of `agents`: one toolbar button per visible agent, one `agent.<id>` tab kind per
/// agent of the catalog, the terminal surface behind each tab (agents R2, R4–R9).
@MainActor
final class AgentsFeature {
    nonisolated struct Payload: Codable, Equatable, Sendable {
        let id: String
        /// config R10: relative to the root when inside it.
        let cwd: String
        /// git R32: the session diff base, kept across a relaunch of the app.
        var session: Session? = nil
    }

    /// git R30, R32: what the session diff of a tab compares against.
    nonisolated struct Session: Codable, Equatable, Sendable {
        let repo: String
        let base: String
    }

    /// agents R4, R6: what a click on the button does.
    nonisolated enum ButtonAction: Equatable, Sendable {
        case activate(TabID)
        case relaunch(TabID)
        case spawn
    }

    private let layout: LayoutManager
    private let workspace: Workspace
    private let terminal: TerminalService
    private let git: GitFeature
    private var catalog: [Agent] = []
    /// git R30: one snapshot per agent tab, taken at spawn and relaunch.
    private var sessions: [TabID: Session] = [:]
    private var snapshots: [TabID: Task<Void, Never>] = [:]
    private var visibleIDs: [String] = []
    /// agents R4: the tab the button reuses, the first one opened or restored for the agent.
    private var primaryTabs: [String: TabID] = [:]
    private var agentOfTab: [TabID: String] = [:]
    /// agents R10: the agent tab the user showed last.
    private var lastActivated: TabID?
    private var registeredKinds: Set<String> = []
    private var configWatch: Task<Void, Never>?
    private var eventsWatch: Task<Void, Never>?
    private var detection: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "agents")

    init(layout: LayoutManager, workspace: Workspace, terminal: TerminalService, git: GitFeature) {
        self.layout = layout
        self.workspace = workspace
        self.terminal = terminal
        self.git = git
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
    }

    isolated deinit {
        configWatch?.cancel()
        eventsWatch?.cancel()
        detection?.cancel()
        for task in snapshots.values {
            task.cancel()
        }
    }

    // MARK: - Catalog and detection (agents R1–R3, US5)

    private func apply(_ config: WorkspaceConfig) {
        let merged: AgentCatalog.Merged
        do {
            merged = AgentCatalog.merge(try config.section("agents", as: [String: AgentCatalog.Entry].self))
        } catch {
            logger.error("agents section ignored: \(error.localizedDescription, privacy: .public)")
            merged = AgentCatalog.merge(nil)
        }
        for warning in merged.warnings {
            logger.warning("\(warning, privacy: .public)")
        }
        catalog = merged.agents
        for agent in catalog {
            register(agent)
        }
        // agents R2: detection follows every accepted config, never a timer.
        detection?.cancel()
        detection = Task { [weak self] in
            await self?.detect()
        }
    }

    private func detect() async {
        let names = Set(catalog.filter(\.isBuiltIn).map(\.binary))
        let path = await workspace.loginEnvironment()["PATH"]
        // Disk IO (agents, technical options): off the main actor.
        let found = await Task.detached { AgentCatalog.executables(among: names, inPath: path) }.value
        guard !Task.isCancelled else { return }
        show(catalog.filter { !$0.isBuiltIn || found.contains($0.binary) }.map(\.id))
    }

    /// The tab kind and the shortcut of an agent exist for its whole life, even hidden, so its
    /// tabs restore (layout R28) and `config.shortcuts` can name it (agents R9).
    private func register(_ agent: Agent) {
        let kind = Self.kind(of: agent.id)
        guard !registeredKinds.contains(kind) else { return }
        registeredKinds.insert(kind)
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: kind, isTerminal: true,
                makeView: { [weak self] id, payload in self?.view(id, payload: payload, agentID: agent.id) },
                serialize: { [weak self] id in self?.serialize(id, agentID: agent.id) },
                confirmClose: { [weak self] id in await self?.terminal.confirmClose(id) ?? true },
                onClose: { [weak self] id in self?.closed(id) }))
        layout.shortcuts.register(
            ShortcutAction(id: "agents.\(agent.id)", title: agent.title, defaultShortcut: nil) { [weak self] in
                self?.buttonClicked(agent.id)
            })
    }

    /// agents R2, layout R30, R33: buttons and home entries of the visible agents, in catalog order.
    private func show(_ ids: [String]) {
        guard ids != visibleIDs || ids.contains(where: { layout.toolbarItem(Self.kind(of: $0))?.title != title($0) })
        else { return }
        for id in visibleIDs {
            layout.removeToolbarItem(Self.kind(of: id))
        }
        visibleIDs = ids
        for id in ids {
            guard let agent = agent(id) else { continue }
            layout.register(
                toolbarItem: ToolbarItemDescriptor(
                    id: Self.kind(of: id), title: agent.title, icon: icon(of: agent), placement: .center,
                    kind: .action(
                        perform: { [weak self] in self?.buttonClicked(id) },
                        secondaryMenu: { [weak self] in self?.menu(for: id) ?? [] })))
            syncBadge(id)
        }
        layout.replaceHomeEntries(
            in: .agents,
            with: ids.compactMap { id in
                agent(id).map { agent in
                    HomeEntry(id: "agents.\(id)", title: agent.title, icon: icon(of: agent), section: .agents) {
                        [weak self] in self?.buttonClicked(id)
                    }
                }
            })
    }

    /// agents R3: a relative `icon` is a file of the workspace (SVG or PNG), never outside it.
    private func icon(of agent: Agent) -> String {
        guard agent.icon.contains("/") || agent.icon.hasSuffix(".svg") || agent.icon.hasSuffix(".png") else {
            return agent.icon
        }
        let file = Workspace.url(forPersistedPath: agent.icon, root: workspace.root).standardizedFileURL
        let path = file.path(percentEncoded: false)
        return path.hasPrefix(workspace.root.standardizedFileURL.path(percentEncoded: false)) ? path : agent.icon
    }

    private func agent(_ id: String) -> Agent? {
        catalog.first { $0.id == id }
    }

    private func title(_ id: String) -> String? {
        agent(id)?.title
    }

    nonisolated static func kind(of agentID: String) -> String {
        "agent.\(agentID)"
    }

    // MARK: - Button (agents R4–R6)

    /// agents R4, R6: the primary tab is activated, relaunched when its process ended, or created.
    nonisolated static func buttonAction(primary: TabID?, state: TerminalState?) -> ButtonAction {
        guard let primary, let state else { return .spawn }
        if case .exited = state { return .relaunch(primary) }
        return .activate(primary)
    }

    private func buttonClicked(_ id: String) {
        let primary = primaryTabs[id].flatMap { layout.model.owner(of: $0) != nil ? $0 : nil }
        switch Self.buttonAction(primary: primary, state: primary.flatMap { terminal.tab($0)?.state }) {
        case .activate(let tab):
            activate(tab)
        case .relaunch(let tab):
            activate(tab)
            // Refused only for a missing folder; the tab's banner says so.
            try? terminal.relaunch(tab)
        case .spawn:
            spawn(id, cwd: workspace.root, primary: true)
        }
    }

    private func activate(_ tab: TabID) {
        guard let owner = layout.model.owner(of: tab) else { return }
        layout.activate(tab, in: owner)
    }

    /// agents R4, R5: a new tab in the active group; the first one becomes the button's.
    private func spawn(_ id: String, cwd: URL, primary: Bool) {
        guard let agent = agent(id) else { return }
        guard
            let tab = terminal.spawn(command: agent.command, cwd: cwd, kind: Self.kind(of: id), title: agent.title)
        else { return }
        agentOfTab[tab] = id
        if primary, primaryTabs[id] == nil {
            primaryTabs[id] = tab
        }
        syncBadge(id)
    }

    // MARK: - Session diff (git R30–R32)

    /// git R30: the working tree snapshotted when the agent's process starts; off the main actor,
    /// the previous snapshot of the tab replaced.
    private func takeSnapshot(of tab: TabID) {
        guard let cwd = terminal.tab(tab)?.cwd else { return }
        snapshots[tab]?.cancel()
        snapshots[tab] = Task { [weak self, git] in
            guard let snapshot = await git.snapshot(for: cwd), !Task.isCancelled, let self else { return }
            sessions[tab] = Session(repo: snapshot.repo, base: snapshot.tree)
        }
    }

    /// git R31a: one entry per agent tab of the window that has a snapshot.
    private func sessionEntries(for id: String) -> [ToolbarMenuEntry] {
        let tabs = agentOfTab.filter { $0.value == id }.keys
            .filter { sessions[$0] != nil && layout.model.owner(of: $0) != nil }
            .sorted { $0.uuid.uuidString < $1.uuid.uuidString }
        return tabs.enumerated().map { index, tab in
            let title = index == 0 ? "Session Changes" : "Session Changes (\(index + 1))"
            return ToolbarMenuEntry(id: "agents.\(id).session.\(tab.uuid.uuidString)", title: title) { [weak self] in
                guard let self, let session = sessions[tab], let agent = agent(id) else { return }
                git.openSessionDiff(repo: session.repo, base: session.base, title: agent.title)
            }
        }
    }

    /// agents R5: the secondary menu of the button.
    private func menu(for id: String) -> [ToolbarMenuEntry] {
        var entries = [
            ToolbarMenuEntry(id: "agents.\(id).new", title: "New Session") { [weak self] in
                guard let self else { return }
                spawn(id, cwd: workspace.root, primary: false)
            }
        ]
        for repo in workspace.config.repos {
            let name = repo.lastPathComponent
            entries.append(
                ToolbarMenuEntry(id: "agents.\(id).in.\(name)", title: "Run in \(name)", subtitle: nil) {
                    [weak self] in self?.spawn(id, cwd: repo, primary: false)
                })
        }
        entries += sessionEntries(for: id)
        return entries
    }

    // MARK: - Tabs (agents R8, layout R28)

    private func view(_ id: TabID, payload: String, agentID: String) -> AnyView? {
        if let view = terminal.view(for: id) {
            agentOfTab[id] = agentID
            if primaryTabs[agentID] == nil {
                primaryTabs[agentID] = id
            }
            return view
        }
        // agents R8: restored idle in its folder, with today's command, never run by itself.
        guard let agent = agent(agentID), let data = payload.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        agentOfTab[id] = agentID
        if primaryTabs[agentID] == nil {
            primaryTabs[agentID] = id
        }
        sessions[id] = decoded.session
        return terminal.restore(
            id, kind: Self.kind(of: agentID), title: agent.title, command: agent.command,
            cwd: Workspace.url(forPersistedPath: decoded.cwd, root: workspace.root))
    }

    private func serialize(_ id: TabID, agentID: String) -> String? {
        guard let tab = terminal.tab(id) else { return nil }
        let payload = Payload(
            id: agentID, cwd: Workspace.persistedPath(for: tab.cwd, root: workspace.root), session: sessions[id])
        // A two-field Codable struct always encodes.
        return String(decoding: (try? JSONEncoder().encode(payload)) ?? Data(), as: UTF8.self)
    }

    private func closed(_ id: TabID) {
        terminal.closed(id)
        sessions[id] = nil
        snapshots.removeValue(forKey: id)?.cancel()
        guard let agentID = agentOfTab.removeValue(forKey: id) else { return }
        if primaryTabs[agentID] == id {
            primaryTabs[agentID] = agentOfTab.first { $0.value == agentID }?.key
        }
        syncBadge(agentID)
    }

    // MARK: - Badges (agents R6, terminal R7)

    private func handle(_ event: TerminalEvent) {
        let tab: TabID
        switch event {
        case .started(let id, _), .exited(let id, _), .bell(let id), .activated(let id), .closed(let id):
            tab = id
        }
        guard let agentID = agentOfTab[tab] else { return }
        switch event {
        case .activated: lastActivated = tab
        // git R30: at every start, whoever relaunched (the button or the surface's own button).
        case .started: takeSnapshot(of: tab)
        case .exited, .bell, .closed: break
        }
        syncBadge(agentID)
    }

    // MARK: - Send to the active agent (agents R10)

    /// agents R10: whether a live agent tab can take a mention (menus are disabled otherwise).
    var canSend: Bool {
        activeAgentTab != nil
    }

    /// agents R10a–R10c: the mention written into the active agent's PTY, its tab shown.
    func send(_ mention: AgentMention) {
        guard let id = activeAgentTab, let tab = terminal.tab(id) else {
            logger.debug("nothing sent: no agent tab")
            return
        }
        do {
            try terminal.write(Array(mention.text(relativeTo: tab.cwd).utf8), to: id)
        } catch {
            logger.error("send failed: \(String(describing: error), privacy: .public)")
            return
        }
        activate(id)
    }

    private var activeAgentTab: TabID? {
        let candidates =
            layout.model.active.tabs.map(\.id).filter { agentOfTab[$0] != nil }
            + agentOfTab.keys.sorted { $0.uuid.uuidString < $1.uuid.uuidString }
        return Self.activeAgentTab(
            lastActivated: lastActivated,
            candidates: candidates.map { ($0, layout.model.owner(of: $0) != nil ? terminal.tab($0)?.state : nil) })
    }

    /// agents R10: the last activated tab when it is still open and not exited, else the first
    /// candidate in that state (`candidates` in bar order, `nil` state = gone).
    nonisolated static func activeAgentTab(
        lastActivated: TabID?, candidates: [(id: TabID, state: TerminalState?)]
    )
        -> TabID?
    {
        func isLive(_ state: TerminalState?) -> Bool {
            switch state {
            case .idle, .running: return true
            case .exited, nil: return false
            }
        }
        if let lastActivated, let last = candidates.first(where: { $0.id == lastActivated }), isLive(last.state) {
            return lastActivated
        }
        return candidates.first { isLive($0.state) }?.id
    }

    /// agents R6: running → green; a marked tab → orange; else none.
    nonisolated static func badge(running: Bool, marked: Bool) -> ToolbarBadge {
        running ? .dot(.green) : (marked ? .dot(.orange) : .none)
    }

    private func syncBadge(_ agentID: String) {
        let tabs = agentOfTab.filter { $0.value == agentID }.keys.compactMap { terminal.tab($0) }
        layout.setBadge(
            Self.badge(running: tabs.contains(where: \.isRunning), marked: tabs.contains(where: \.isMarked)),
            on: Self.kind(of: agentID))
    }
}
