import CoreGraphics
import SwiftUI
import Testing

@testable import Wraith

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
}
