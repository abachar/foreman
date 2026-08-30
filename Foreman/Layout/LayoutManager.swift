import AppKit
import CoreGraphics
import Foundation
import Observation
import SwiftUI
import os

/// Owner of a window's layout: the center model, the panels, the shortcut table, the slot sizes.
///
/// Views read it and send intentions; features register through it at startup. The layout's own
/// actions (layout R23) are registered here, as `isLayout`, so a feature cannot take them (R24).
@Observable
@MainActor
final class LayoutManager {
    var model = LayoutModel()
    let panels = PanelManager()
    let shortcuts = ShortcutRegistry()
    private(set) var homeEntries: [HomeEntry] = []
    /// layout R30: in registration order; `WorkspaceToolbar` splits leading and trailing.
    private(set) var toolbarItems: [ToolbarItemDescriptor] = []
    private(set) var badges: [String: ToolbarBadge] = [:]
    /// layout R32: `cmd+opt+t`, persisted.
    var isToolbarVisible = true
    /// layout R27: where the window was; `nil` until the window reports it.
    var windowFrame: CGRect?

    /// layout R18 (amended 2026-08-28): one persisted thickness per panel.
    private(set) var panelSizes: [PanelID: CGFloat] = [:]
    /// The room the center zone currently has; geometry (R11, R12) depends on it.
    var centerSize = CGSize(width: 1100, height: 700)

    /// `cmd+shift+n` (layout R23): opening a folder is the app's, not the layout's.

    var tabKinds: [String: CenterTabDescriptor] = [:]
    var tabViews: [TabID: AnyView] = [:]
    private let logger = Logger(subsystem: "dev.crafters.foreman", category: "layout")

    init() {
        registerLayoutActions()
    }

    // MARK: - Registration

    /// Registers a panel and its toggle shortcut (layout R3, R22).
    func register(panel: PanelDescriptor) {
        guard panels.register(panel) else { return }
        shortcuts.register(
            ShortcutAction(id: panel.id.rawValue, title: panel.title, defaultShortcut: panel.defaultShortcut) {
                [panels] in
                panels.toggle(panel.id)
            })
        // layout R30 (2026-08-27), design R15: a toggle in the toolbar for the left and right slots.
        guard panel.side != .bottom else { return }
        register(
            toolbarItem: ToolbarItemDescriptor(
                id: Self.toggleID(of: panel.id), title: panel.title, icon: panel.icon,
                placement: panel.side == .left ? .leading : .trailing,
                kind: .action(perform: { [panels] in panels.toggle(panel.id) }, secondaryMenu: nil)))
    }

    /// layout R36: the panel, its toggle shortcut and its toolbar toggle go together.
    func unregister(panel id: PanelID) {
        guard panels[id] != nil else { return }
        panels.unregister(id)
        shortcuts.unregister(id.rawValue)
        removeToolbarItem(Self.toggleID(of: id))
    }

    /// The toolbar item that toggles a panel; `nil` for an item that is not one.
    nonisolated static func toggleID(of panel: PanelID) -> String {
        "layout.panel.\(panel.rawValue)"
    }

    nonisolated static func panelID(ofToggle itemID: String) -> PanelID? {
        itemID.hasPrefix("layout.panel.") ? PanelID(String(itemID.dropFirst("layout.panel.".count))) : nil
    }

    func register(tabKind descriptor: CenterTabDescriptor) {
        guard tabKinds[descriptor.kind] == nil else {
            logger.fault("tab kind \(descriptor.kind, privacy: .public) registered twice, second refused")
            return
        }
        tabKinds[descriptor.kind] = descriptor
    }

    /// layout R33: same rules as toolbar items, a duplicated id is refused.
    /// layout R33: a section whose entries change over time (recent files, editor R19).
    func replaceHomeEntries(in section: HomeEntry.Section, with entries: [HomeEntry]) {
        homeEntries.removeAll { $0.section == section }
        homeEntries.append(contentsOf: entries)
    }

    func register(homeEntry: HomeEntry) {
        guard !homeEntries.contains(where: { $0.id == homeEntry.id }) else {
            logger.fault("home entry \(homeEntry.id, privacy: .public) registered twice, second refused")
            return
        }
        homeEntries.append(homeEntry)
    }

    /// layout R31: a duplicated id is refused and logged as a fault.
    @discardableResult
    func register(toolbarItem descriptor: ToolbarItemDescriptor) -> Bool {
        guard toolbarItem(descriptor.id) == nil else {
            logger.fault("toolbar item \(descriptor.id, privacy: .public) registered twice, second refused")
            return false
        }
        toolbarItems.append(descriptor)
        return true
    }

    func toolbarItem(_ id: String) -> ToolbarItemDescriptor? {
        toolbarItems.first { $0.id == id }
    }

    /// agents R2, US5: an agent that disappears from the config or the PATH loses its button.
    func removeToolbarItem(_ id: String) {
        toolbarItems.removeAll { $0.id == id }
        badges[id] = nil
    }

    func setBadge(_ badge: ToolbarBadge, on itemID: String) {
        badges[itemID] = badge
    }

    func badge(of itemID: String) -> ToolbarBadge {
        badges[itemID] ?? .none
    }

    // MARK: - Tabs

    /// Opens a tab of `kind` in the active group (layout R14, R17); `nil` when the kind is unknown
    /// or its feature refuses the payload.
    ///
    /// `newGroup` (explorer R13) splits the active group to the right first; when the split is
    /// refused (edge cases: minimum size) the tab opens in the active group, without a beep.
    @discardableResult
    func openTab(
        kind: String, title: String, payload: String, newGroup: Bool = false, isPreview: Bool = false
    )
        -> TabID?
    {
        let tab = Tab(kind: kind, title: title, isPreview: isPreview)
        guard let view = tabKinds[kind]?.makeView(tab.id, payload) else { return nil }
        tabViews[tab.id] = view
        if newGroup {
            _ = model.split(.vertical, in: centerSize)
        }
        model.open(tab)
        panels.focusCenter()
        return tab.id
    }

    func view(for tab: Tab) -> AnyView? {
        tabViews[tab.id]
    }

    func update(_ id: TabID, title: String, isDirty: Bool, isPreview: Bool = false, badge: ToolbarBadge = .none) {
        model.update(id, title: title, isDirty: isDirty, isPreview: isPreview, badge: badge)
    }

    /// layout R25: the active tab of the active group is a terminal surface.
    var isTerminalTabActive: Bool {
        guard let kind = model.active.active?.kind else { return false }
        return tabKinds[kind]?.isTerminal == true
    }

    func activate(_ id: TabID, in group: GroupID) {
        model.activate(id, in: group)
        panels.focusCenter()
    }

    func activateGroup(_ id: GroupID) {
        model = model.activating(id)
        panels.focusCenter()
    }

    /// layout R38: what the double click of the tab bar and of the home screen opens, set by the
    /// feature that owns untitled tabs (`editor` R34).
    ///
    /// The layout does not know what an untitled tab is, exactly as it knows no home entry inline
    /// (R33): unset, the double click does nothing.
    var onNewTab: (() -> Void)?

    /// layout R38: an untitled tab in `group` — the group takes the focus first, so the tab opens
    /// where it was asked for and not in the one that happened to be active.
    func newTab(in group: GroupID) {
        activateGroup(group)
        onNewTab?()
    }

    /// layout R15: a dirty tab is closed only once its owner confirmed.
    func closeTab(_ id: TabID) async {
        guard let owner = model.owner(of: id), let tab = model[group: owner]?.tabs.first(where: { $0.id == id })
        else { return }
        if tab.isDirty, let descriptor = tabKinds[tab.kind], !(await descriptor.confirmClose(id)) {
            return
        }
        model.close(id)
        tabViews[id] = nil
        tabKinds[tab.kind]?.onClose(id)
    }

    /// layout R35: the menu's multi-tab entries, one `closeTab` at a time in bar order; a tab
    /// still there after its turn (R15 refusal) stops the rest.
    func closeTabs(_ selection: TabCloseSelection, around id: TabID) async {
        guard let owner = model.owner(of: id), let group = model[group: owner] else { return }
        for tab in group.tabs(toClose: selection, around: id) {
            await closeTab(tab.id)
            if model.owner(of: tab.id) != nil {
                return
            }
        }
    }

    /// layout R15: confirmations one by one, in reading order; a refusal stops everything.
    func confirmCloseAll() async -> Bool {
        for tab in model.dirtyTabs() {
            guard let descriptor = tabKinds[tab.kind] else { continue }
            if !(await descriptor.confirmClose(tab.id)) {
                return false
            }
        }
        return true
    }

    // MARK: - Groups

    /// layout R9: the active tab goes with the split; one tab alone has nothing to split.
    func split(_ orientation: SplitOrientation) {
        // layout, edge cases: refused under the minimum size or with one tab, with the system beep.
        if !model.splitMovingActiveTab(orientation, in: centerSize) {
            NSSound.beep()
        }
    }

    func focusGroup(_ direction: Direction) {
        _ = model.focus(direction, in: centerSize)
        panels.focusCenter()
    }

    func moveActiveTab(_ direction: Direction) {
        _ = model.moveActiveTab(direction, in: centerSize)
    }

    /// The thickness each visible slot asks for: its panel's, or the slot's default (layout R18, R19).
    var requestedSizes: [PanelSide: CGFloat] {
        panels.visible.reduce(into: [:]) { sizes, entry in
            sizes[entry.key] = panelSizes[entry.value] ?? ZoneSizing.defaults[entry.key]
        }
    }

    /// The user dragged a divider (layout R18); automatic adjustments never come through here.
    func setPanelSize(_ size: CGFloat, for side: PanelSide) {
        guard let id = panels.visible[side] else { return }
        setPanelSize(size, of: id)
    }

    func setPanelSize(_ size: CGFloat, of id: PanelID) {
        panelSizes[id] = max(size, ZoneSizing.minimumPanel)
    }

    // MARK: - Layout actions (layout R23)

    private func registerLayoutActions() {
        let actions: [(String, String, String, () -> Void)] = [
            ("layout.tab.close", "Close Tab", "cmd+w", { [weak self] in self?.closeActiveTab() }),
            (
                "layout.tab.previous", "Previous Tab", "cmd+shift+[",
                { [weak self] in self?.model.updateActiveGroup { $0.activatePrevious() } }
            ),
            (
                "layout.tab.next", "Next Tab", "cmd+shift+]",
                { [weak self] in self?.model.updateActiveGroup { $0.activateNext() } }
            ),
            ("layout.split.vertical", "Split Right", "cmd+d", { [weak self] in self?.split(.vertical) }),
            ("layout.split.horizontal", "Split Down", "cmd+shift+d", { [weak self] in self?.split(.horizontal) }),
            ("layout.focus.left", "Focus Group Left", "cmd+opt+left", { [weak self] in self?.focusGroup(.left) }),
            ("layout.focus.right", "Focus Group Right", "cmd+opt+right", { [weak self] in self?.focusGroup(.right) }),
            ("layout.focus.up", "Focus Group Above", "cmd+opt+up", { [weak self] in self?.focusGroup(.up) }),
            ("layout.focus.down", "Focus Group Below", "cmd+opt+down", { [weak self] in self?.focusGroup(.down) }),
            ("layout.move.left", "Move Tab Left", "cmd+opt+shift+left", { [weak self] in self?.moveActiveTab(.left) }),
            (
                "layout.move.right", "Move Tab Right", "cmd+opt+shift+right",
                { [weak self] in self?.moveActiveTab(.right) }
            ),
            ("layout.move.up", "Move Tab Up", "cmd+opt+shift+up", { [weak self] in self?.moveActiveTab(.up) }),
            ("layout.move.down", "Move Tab Down", "cmd+opt+shift+down", { [weak self] in self?.moveActiveTab(.down) }),
            (
                "layout.toolbar.toggle", "Toggle Toolbar", "cmd+opt+t",
                { [weak self] in self?.isToolbarVisible.toggle() }
            ),
        ]
        for (id, title, shortcut, perform) in actions {
            shortcuts.register(
                ShortcutAction(id: id, title: title, defaultShortcut: shortcut, isLayout: true, perform: perform))
        }
        // layout R23: `escape` from a panel only; at the center it belongs to the content (find bar…).
        shortcuts.register(
            ShortcutAction(
                id: "layout.focus.center", title: "Focus Center", scope: .panel, defaultShortcut: "escape",
                isLayout: true
            ) {
                [weak self] in self?.panels.focusCenter()
            })
        for number in 1...9 {
            shortcuts.register(
                ShortcutAction(
                    id: "layout.tab.\(number)", title: "Tab \(number)", defaultShortcut: "cmd+\(number)", isLayout: true
                ) {
                    [weak self] in
                    self?.model.updateActiveGroup { $0.activate(number: number) }
                })
        }
    }

    private func closeActiveTab() {
        guard let tab = model.active.active else { return }
        Task { await closeTab(tab.id) }
    }
}
