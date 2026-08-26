import CoreGraphics
import Foundation

/// The center zone as a value: the split tree, its groups and the active group (layout R7–R17).
///
/// Every operation is pure; `LayoutManager` owns one and exposes it to the views. The center size
/// is passed in because geometry depends on it (R11, R12, split refusal).
nonisolated struct LayoutModel: Equatable, Sendable {
    private(set) var tree: LayoutNode
    private(set) var groups: [GroupID: TabGroup]
    /// layout R17: exactly one active group.
    private(set) var activeGroup: GroupID

    init() {
        let group = TabGroup()
        tree = .group(group.id)
        groups = [group.id: group]
        activeGroup = group.id
    }

    init(tree: LayoutNode, groups: [GroupID: TabGroup], activeGroup: GroupID) {
        self.tree = tree
        self.groups = groups
        self.activeGroup = tree.contains(activeGroup) ? activeGroup : tree.groups[0]
    }

    var active: TabGroup {
        // The active group is always in `groups`: every mutation below keeps it so.
        groups[activeGroup] ?? TabGroup(id: activeGroup)
    }

    subscript(group id: GroupID) -> TabGroup? {
        groups[id]
    }

    // MARK: - Groups

    func activating(_ id: GroupID) -> LayoutModel {
        guard groups[id] != nil else { return self }
        var model = self
        model.activeGroup = id
        return model
    }

    /// layout R9: a new empty sibling, active. `false` when refused (edge cases: minimum size).
    mutating func split(_ orientation: SplitOrientation, in size: CGSize) -> Bool {
        guard tree.canSplit(activeGroup, orientation, in: size) else { return false }
        let group = TabGroup()
        tree = tree.splitting(activeGroup, orientation, adding: group.id)
        groups[group.id] = group
        activeGroup = group.id
        return true
    }

    /// layout R11: focus the neighbor in `direction`; `false` when there is none.
    mutating func focus(_ direction: Direction, in size: CGSize) -> Bool {
        guard let neighbor = tree.neighbor(of: activeGroup, direction, in: size) else { return false }
        activeGroup = neighbor
        return true
    }

    // MARK: - Tabs

    /// Opens `tab` in the active group (layout R14, R17).
    mutating func open(_ tab: Tab) {
        groups[activeGroup]?.insert(tab)
    }

    mutating func activate(_ id: TabID, in group: GroupID) {
        groups[group]?.activate(id)
        activeGroup = group
    }

    mutating func updateActiveGroup(_ change: (inout TabGroup) -> Void) {
        guard var group = groups[activeGroup] else { return }
        change(&group)
        groups[activeGroup] = group
    }

    mutating func update(_ id: TabID, title: String, isDirty: Bool, isPreview: Bool = false) {
        guard let owner = owner(of: id) else { return }
        groups[owner]?.update(id, title: title, isDirty: isDirty, isPreview: isPreview)
    }

    /// Removes the tab; layout R10: an emptied group closes unless it is the last one.
    @discardableResult
    mutating func close(_ id: TabID) -> Tab? {
        guard let owner = owner(of: id), let tab = groups[owner]?.remove(id) else { return nil }
        if groups[owner]?.isEmpty == true, tree.groups.count > 1 {
            closeGroup(owner)
        }
        return tab
    }

    /// layout R12: the active tab goes to the neighbor group and becomes its active tab.
    mutating func moveActiveTab(_ direction: Direction, in size: CGSize) -> Bool {
        guard let tab = active.active, let target = tree.neighbor(of: activeGroup, direction, in: size) else {
            return false
        }
        close(tab.id)
        groups[target]?.insert(tab)
        activeGroup = target
        return true
    }

    /// The tabs whose owner must confirm before `group` closes (layout R15), in order.
    func dirtyTabs(in group: GroupID? = nil) -> [Tab] {
        let ids = group.map { [$0] } ?? tree.groups
        return ids.flatMap { groups[$0]?.tabs.filter(\.isDirty) ?? [] }
    }

    func owner(of id: TabID) -> GroupID? {
        groups.values.first { $0.tabs.contains { $0.id == id } }?.id
    }

    private mutating func closeGroup(_ id: GroupID) {
        guard tree.groups.count > 1 else { return }
        tree = tree.closing(id)
        groups[id] = nil
        if activeGroup == id {
            activeGroup = tree.groups[0]
        }
    }
}
