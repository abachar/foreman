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
