import Foundation

/// Stable identity of a tab; generated at creation and persisted (layout R13).
nonisolated struct TabID: Hashable, Codable, Sendable {
    let uuid: UUID

    init() {
        uuid = UUID()
    }

    init(from decoder: Decoder) throws {
        uuid = try decoder.singleValueContainer().decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuid)
    }
}

/// What the layout knows about a tab (layout R13): the owner feature provides title and dirtiness.
nonisolated struct Tab: Identifiable, Equatable, Sendable {
    let id: TabID
    /// Namespaced id declared by a feature (`editor.file`, `agent.claude`).
    let kind: String
    var title: String
    var isDirty = false
    /// editor R2: shown in italics; the owner decides when it becomes pinned.
    var isPreview = false
    /// terminal R7: a mark set by the owner (process running, bell, exit), never persisted.
    var badge: ToolbarBadge = .none

    init(
        id: TabID = TabID(), kind: String, title: String, isDirty: Bool = false, isPreview: Bool = false,
        badge: ToolbarBadge = .none
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.isDirty = isDirty
        self.isPreview = isPreview
        self.badge = badge
    }
}

/// An ordered list of tabs and the active one (layout R13, R14).
nonisolated struct TabGroup: Equatable, Sendable {
    let id: GroupID
    private(set) var tabs: [Tab] = []
    private(set) var activeTab: TabID?

    init(id: GroupID = GroupID()) {
        self.id = id
    }

    var isEmpty: Bool { tabs.isEmpty }

    var active: Tab? {
        tabs.first { $0.id == activeTab }
    }

    private var activeIndex: Int? {
        tabs.firstIndex { $0.id == activeTab }
    }

    /// layout R14: right after the active tab, and active.
    mutating func insert(_ tab: Tab) {
        tabs.insert(tab, at: activeIndex.map { $0 + 1 } ?? tabs.count)
        activeTab = tab.id
    }

    /// layout R14: closing the active tab activates its left neighbor, or the first tab.
    @discardableResult
    mutating func remove(_ id: TabID) -> Tab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = tabs.remove(at: index)
        if activeTab == id {
            activeTab = tabs.isEmpty ? nil : tabs[max(index - 1, 0)].id
        }
        return removed
    }

    mutating func activate(_ id: TabID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTab = id
    }

    /// `cmd+1…9`: 1-based; 9 is the last tab; beyond the count, no effect (layout R23, edge cases).
    mutating func activate(number: Int) {
        guard !tabs.isEmpty, number >= 1 else { return }
        if number == 9 {
            activeTab = tabs[tabs.count - 1].id
        } else if number <= tabs.count {
            activeTab = tabs[number - 1].id
        }
    }

    mutating func activateNext() {
        step(by: 1)
    }

    mutating func activatePrevious() {
        step(by: -1)
    }

    mutating func update(
        _ id: TabID, title: String, isDirty: Bool, isPreview: Bool = false, badge: ToolbarBadge = .none
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].title = title
        tabs[index].isDirty = isDirty
        tabs[index].isPreview = isPreview
        tabs[index].badge = badge
    }

    /// layout R35: what a menu entry closes, in bar order, around the clicked tab.
    func tabs(toClose selection: TabCloseSelection, around id: TabID) -> [Tab] {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return [] }
        switch selection {
        case .others: return tabs.filter { $0.id != id }
        case .all: return tabs
        case .unmodified: return tabs.filter { !$0.isDirty }
        case .left: return Array(tabs[..<index])
        case .right: return Array(tabs[(index + 1)...])
        }
    }

    private mutating func step(by offset: Int) {
        guard let index = activeIndex, tabs.count > 1 else { return }
        activeTab = tabs[(index + offset + tabs.count) % tabs.count].id
    }
}

/// layout R35: the multi-tab entries of the tab menu.
nonisolated enum TabCloseSelection: CaseIterable, Sendable {
    case others
    case all
    case unmodified
    case left
    case right

    var title: String {
        switch self {
        case .others: return "Close Other Tabs"
        case .all: return "Close All Tabs"
        case .unmodified: return "Close Unmodified Tabs"
        case .left: return "Close Tabs to the Left"
        case .right: return "Close Tabs to the Right"
        }
    }
}
