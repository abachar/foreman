import AppKit
import Foundation

/// layout R27–R29: what is persisted, and how it comes back.
extension LayoutManager {
    /// The state to persist now; tabs whose feature returns no payload are left out.
    func snapshot() -> LayoutState {
        let groups = model.tree.groups.compactMap { id -> LayoutState.GroupState? in
            guard let group = model[group: id] else { return nil }
            let tabs = group.tabs.compactMap { tab -> LayoutState.TabState? in
                guard let payload = tabKinds[tab.kind]?.serialize(tab.id) else { return nil }
                return LayoutState.TabState(id: tab.id, kind: tab.kind, title: tab.title, payload: payload)
            }
            let activeTab = tabs.contains { $0.id == group.activeTab } ? group.activeTab : tabs.first?.id
            return LayoutState.GroupState(id: id, tabs: tabs, activeTab: activeTab)
        }
        return LayoutState(
            tree: model.tree,
            groups: groups,
            activeGroup: model.activeGroup,
            panels: panels.visible,
            panelSizes: panelSizes,
            windowFrame: windowFrame,
            isToolbarVisible: isToolbarVisible
        )
    }

    /// layout R29: tree and groups, then tabs, then panels, then the active group.
    ///
    /// Visible panels are not activated here but by `PanelManager.activateVisible()` after the
    /// first frame. A tab of an unknown kind, or one its feature cannot restore, is ignored; a group left
    /// empty folds unless it is the last one (R28, R10).
    func restore(_ state: LayoutState) {
        var tree = state.tree
        var groups: [GroupID: TabGroup] = [:]
        for groupState in state.groups where tree.contains(groupState.id) {
            var group = TabGroup(id: groupState.id)
            for tabState in groupState.tabs {
                guard let view = tabKinds[tabState.kind]?.makeView(tabState.id, tabState.payload) else { continue }
                tabViews[tabState.id] = view
                group.insert(Tab(id: tabState.id, kind: tabState.kind, title: tabState.title))
            }
            if let activeTab = groupState.activeTab {
                group.activate(activeTab)
            }
            groups[groupState.id] = group
        }
        for id in tree.groups where groups[id] == nil {
            groups[id] = TabGroup(id: id)
        }
        for id in tree.groups where groups[id]?.isEmpty == true && tree.groups.count > 1 {
            tree = tree.closing(id)
            groups[id] = nil
        }
        model = LayoutModel(tree: tree, groups: groups, activeGroup: state.activeGroup)
        panels.restore(visible: state.panels)
        // layout R18: a size of a panel that no longer exists (or a pre-2026-08-28 per-slot key) is dropped.
        for (id, size) in state.panelSizes where panels[id] != nil {
            setPanelSize(size, of: id)
        }
        windowFrame = state.windowFrame
        isToolbarVisible = state.isToolbarVisible
        panels.focusCenter()
    }

    /// layout, edge cases: a persisted frame off every screen is recentered on the main screen,
    /// its size bounded by it.
    static func frameToRestore(_ frame: CGRect, screens: [CGRect], main: CGRect) -> CGRect {
        if screens.contains(where: { $0.intersects(frame) && $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }) {
            return frame
        }
        let size = CGSize(width: min(frame.width, main.width), height: min(frame.height, main.height))
        return CGRect(
            x: main.midX - size.width / 2, y: main.midY - size.height / 2, width: size.width, height: size.height)
    }
}
