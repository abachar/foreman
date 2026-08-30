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

    /// audit L1: `cmd+w` pressed twice must not stack two dialogs on the same tab.
    @Test func aSecondCloseOfTheSameTabAsksNothing() async {
        let layout = LayoutManager()
        nonisolated(unsafe) var asked = 0
        layout.register(
            tabKind: CenterTabDescriptor(
                kind: "editor.file", makeView: { _, payload in AnyView(Text(payload)) }, serialize: { _ in nil },
                confirmClose: { _ in
                    asked += 1
                    // Long enough that the second close starts while this one is still open.
                    try? await Task.sleep(for: .milliseconds(50))
                    return true
                }))
        guard let tab = layout.openTab(kind: "editor.file", title: "a", payload: "a") else {
            Issue.record("tab not opened")
            return
        }
        layout.update(tab, title: "a", isDirty: true)

        async let first: Void = layout.closeTab(tab)
        async let second: Void = layout.closeTab(tab)
        _ = await (first, second)

        #expect(asked == 1)
        #expect(layout.model.active.tabs.isEmpty)
    }

    /// audit L5: a replaced section obeys the same duplicate-id rule as a registered entry.
    @Test func replacedHomeEntriesRefuseADuplicateID() {
        let layout = LayoutManager()
        layout.register(
            homeEntry: HomeEntry(id: "recent.a", title: "a", icon: "doc", section: .recent, action: {}))
        layout.replaceHomeEntries(
            in: .recent,
            with: [
                HomeEntry(id: "recent.b", title: "b", icon: "doc", section: .recent, action: {}),
                HomeEntry(id: "recent.b", title: "b again", icon: "doc", section: .recent, action: {}),
            ])
        #expect(layout.homeEntries.filter { $0.section == .recent }.map(\.id) == ["recent.b"])
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
