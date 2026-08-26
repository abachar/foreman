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

    /// layout R18: one persisted thickness per slot, whatever panel is shown.
    private(set) var panelSizes = ZoneSizing.defaults
    /// The room the center zone currently has; geometry (R11, R12) depends on it.
    var centerSize = CGSize(width: 1100, height: 700)

    /// `cmd+shift+n` (layout R23): opening a folder is the app's, not the layout's.
    var openFolder: () -> Void = {}

    var tabKinds: [String: CenterTabDescriptor] = [:]
    var tabViews: [TabID: AnyView] = [:]
    private let logger = Logger(subsystem: "dev.crafters.wraith", category: "layout")

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
    }

    func register(tabKind descriptor: CenterTabDescriptor) {
        guard tabKinds[descriptor.kind] == nil else {
            logger.fault("tab kind \(descriptor.kind, privacy: .public) registered twice, second refused")
            return
        }
        tabKinds[descriptor.kind] = descriptor
    }

    /// layout R33: same rules as toolbar items, a duplicated id is refused.
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

    func update(_ id: TabID, title: String, isDirty: Bool, isPreview: Bool = false) {
        model.update(id, title: title, isDirty: isDirty, isPreview: isPreview)
    }

    func activate(_ id: TabID, in group: GroupID) {
        model.activate(id, in: group)
        panels.focusCenter()
    }

    func activateGroup(_ id: GroupID) {
        model = model.activating(id)
        panels.focusCenter()
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

    func split(_ orientation: SplitOrientation) {
        // layout, edge cases: refused under 400 x 200 pt per group, with the system beep.
        if !model.split(orientation, in: centerSize) {
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

    /// The user dragged a divider (layout R18); automatic adjustments never come through here.
    func setPanelSize(_ size: CGFloat, for side: PanelSide) {
        panelSizes[side] = max(size, ZoneSizing.minimumPanel)
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
            ("layout.focus.center", "Focus Center", "escape", { [weak self] in self?.panels.focusCenter() }),
            ("layout.window.new", "New Window", "cmd+shift+n", { [weak self] in self?.openFolder() }),
            (
                "layout.toolbar.toggle", "Toggle Toolbar", "cmd+opt+t",
                { [weak self] in self?.isToolbarVisible.toggle() }
            ),
        ]
        for (id, title, shortcut, perform) in actions {
            shortcuts.register(
                ShortcutAction(id: id, title: title, defaultShortcut: shortcut, isLayout: true, perform: perform))
        }
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
