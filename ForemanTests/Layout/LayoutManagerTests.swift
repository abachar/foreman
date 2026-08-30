import CoreGraphics
import SwiftUI
import Testing

@testable import Foreman

/// Opening tabs through the manager (layout R14; explorer R13 for `newGroup`).
@MainActor
struct LayoutManagerTests {
    private func manager() -> LayoutManager {
        let layout = LayoutManager()
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: "editor.file", makeView: { _, payload in AnyView(Text(payload)) }, serialize: { _ in nil }))
        return layout
    }

    /// layout R38: the double click names the group; the tab must not land in whichever one
    /// happened to be active.
    @Test func newTabOpensInTheGroupItWasAskedFor() {
        let layout = manager()
        layout.openTab(kind: "editor.file", title: "a", payload: "a")
        let first = layout.model.activeGroup
        layout.openTab(kind: "editor.file", title: "b", payload: "b", newGroup: true)
        let second = layout.model.activeGroup
        #expect(first != second)
        var opened = 0
        layout.onNewTab = {
            opened += 1
            layout.openTab(kind: "editor.file", title: "Untitled", payload: "u")
        }

        layout.newTab(in: first)

        #expect(opened == 1)
        #expect(layout.model.activeGroup == first)
        #expect(layout.model[group: first]?.tabs.map(\.title) == ["a", "Untitled"])
        #expect(layout.model[group: second]?.tabs.map(\.title) == ["b"])
    }

    /// layout R38: nothing owns untitled tabs in this window, so the double click does nothing.
    @Test func newTabDoesNothingWhenNoFeatureOwnsIt() {
        let layout = manager()
        layout.openTab(kind: "editor.file", title: "a", payload: "a")

        layout.newTab(in: layout.model.activeGroup)

        #expect(layout.model.active.tabs.count == 1)
    }

    @Test func newGroupOpensTheTabInASiblingOnTheRight() {
        let layout = manager()
        layout.openTab(kind: "editor.file", title: "a", payload: "a")
        let first = layout.model.activeGroup

        layout.openTab(kind: "editor.file", title: "b", payload: "b", newGroup: true)

        #expect(layout.model.tree.groups.count == 2)
        #expect(layout.model.activeGroup != first)
        #expect(layout.model.active.tabs.map(\.title) == ["b"])
        #expect(layout.model[group: first]?.tabs.map(\.title) == ["a"])
    }

    @Test func newGroupFallsBackToTheActiveGroupWhenTheSplitIsRefused() {
        let layout = manager()
        layout.centerSize = CGSize(width: 500, height: 400)
        layout.openTab(kind: "editor.file", title: "a", payload: "a")

        layout.openTab(kind: "editor.file", title: "b", payload: "b", newGroup: true)

        #expect(layout.model.tree.groups.count == 1)
        #expect(layout.model.active.tabs.map(\.title) == ["a", "b"])
    }

    @Test func unknownKindOpensNothing() {
        let layout = manager()
        #expect(layout.openTab(kind: "nope", title: "x", payload: "x", newGroup: true) == nil)
        #expect(layout.model.tree.groups.count == 1)
    }

    @Test func badgeFollowsTheTab() {
        let layout = manager()
        let id = layout.openTab(kind: "editor.file", title: "a", payload: "a")!

        layout.update(id, title: "a", isDirty: true, badge: .dot(.green))

        #expect(layout.model.active.active?.badge == .dot(.green))
        #expect(layout.model.active.active?.isDirty == true)
    }

    @Test func closingTellsTheOwnerOnceTheTabIsGone() async {
        let layout = LayoutManager()
        var closed: [TabID] = []
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: "agent.claude", isTerminal: true, makeView: { _, _ in AnyView(EmptyView()) },
                serialize: { _ in nil }, onClose: { closed.append($0) }))
        let id = layout.openTab(kind: "agent.claude", title: "Claude", payload: "")!
        #expect(layout.isTerminalTabActive)

        await layout.closeTab(id)

        #expect(closed == [id])
        #expect(!layout.isTerminalTabActive)
    }

    /// layout R15: `cmd+w` twice on a dirty tab put two confirmations on the screen — the tab is
    /// still in the model while its owner is being asked.
    @Test func asksOnceWhileTheCloseOfATabIsAlreadyBeingConfirmed() async {
        let layout = LayoutManager()
        nonisolated(unsafe) var asked = 0
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: "editor.file", makeView: { _, payload in AnyView(Text(payload)) }, serialize: { _ in nil },
                confirmClose: { id in
                    asked += 1
                    // The user presses `cmd+w` again while the question is on the screen.
                    if asked == 1 {
                        await layout.closeTab(id)
                    }
                    return true
                }))
        guard let id = layout.openTab(kind: "editor.file", title: "a", payload: "a") else {
            Issue.record("tab not opened")
            return
        }
        layout.update(id, title: "a", isDirty: true)

        await layout.closeTab(id)

        #expect(asked == 1)
        #expect(layout.model.active.tabs.isEmpty)
    }

    @Test func removesAToolbarItemWithItsBadge() {
        let layout = LayoutManager()
        layout.register(
            toolbarItem: ToolbarItemDescriptor(
                id: "agent.claude", title: "Claude", icon: "circle", placement: .leading,
                kind: .action(perform: {}, secondaryMenu: nil)))
        layout.setBadge(.dot(.green), on: "agent.claude")

        layout.removeToolbarItem("agent.claude")

        #expect(layout.toolbarItem("agent.claude") == nil)
        #expect(layout.badge(of: "agent.claude") == .none)
    }

    /// layout R33: a recents entry colliding with a registered id gave the home screen two rows
    /// of the same identity.
    @Test func replacingASectionRefusesAnIDAlreadyTaken() {
        let layout = LayoutManager()
        let entry = { (id: String, section: HomeEntry.Section) in
            HomeEntry(id: id, title: id, icon: "circle", section: section, action: {})
        }
        layout.register(homeEntry: entry("agents.claude", .agents))

        layout.replaceHomeEntries(
            in: .recent, with: [entry("agents.claude", .recent), entry("editor.recent.a", .recent)])

        #expect(layout.homeEntries.map(\.id) == ["agents.claude", "editor.recent.a"])
        #expect(layout.homeEntries.map(\.section) == [.agents, .recent])

        layout.replaceHomeEntries(in: .recent, with: [entry("editor.recent.b", .recent)])
        #expect(layout.homeEntries.map(\.id) == ["agents.claude", "editor.recent.b"])
    }

    // MARK: - layout R35

    @Test func closesTheSelectionInBarOrderAndStopsAtARefusal() async {
        let layout = LayoutManager()
        nonisolated(unsafe) var asked: [TabID] = []
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: "editor.file", makeView: { _, payload in AnyView(Text(payload)) }, serialize: { _ in nil },
                confirmClose: { id in
                    asked.append(id)
                    return false
                }))
        layout.openTab(kind: "editor.file", title: "a", payload: "a")
        let b = layout.openTab(kind: "editor.file", title: "b", payload: "b")
        layout.openTab(kind: "editor.file", title: "c", payload: "c")
        let d = layout.openTab(kind: "editor.file", title: "d", payload: "d")
        guard let b, let d else {
            Issue.record("tabs not opened")
            return
        }
        layout.update(b, title: "b", isDirty: true)

        await layout.closeTabs(.others, around: d)

        // `a` went, `b` refused and stopped the rest: `c` stays.
        #expect(layout.model.active.tabs.map(\.title) == ["b", "c", "d"])
        #expect(asked == [b])
    }
}
