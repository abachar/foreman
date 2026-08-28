import CoreGraphics
import Foundation
import Testing

@testable import Foreman

/// Groups and tabs together (layout R9–R12, R15, R17).
struct LayoutModelTests {
    private let size = CGSize(width: 1600, height: 800)

    @Test func startsWithOneEmptyActiveGroup() {
        let model = LayoutModel()

        #expect(model.tree == .group(model.activeGroup))
        #expect(model.active.isEmpty)
    }

    @Test func splitCreatesAnEmptyActiveSibling() {
        var model = LayoutModel()
        let first = model.activeGroup
        model.open(Tab(kind: "demo.hello", title: "a"))

        let didSplit = model.split(.vertical, in: size)
        #expect(didSplit)

        #expect(model.activeGroup != first)
        #expect(model.active.isEmpty)
        #expect(model.tree.groups == [first, model.activeGroup])
    }

    @Test func splitCommandMovesTheActiveTabIntoTheNewSibling() {
        var model = LayoutModel()
        let first = model.activeGroup
        let a = Tab(kind: "demo.hello", title: "a")
        let b = Tab(kind: "demo.hello", title: "b")
        model.open(a)
        model.open(b)

        let didSplit = model.splitMovingActiveTab(.vertical, in: size)
        #expect(didSplit)

        // layout R9 (2026-08-28): `b` left with the split, `a` stays and is active there.
        #expect(model.activeGroup != first)
        #expect(model.active.tabs == [b])
        #expect(model[group: first]?.tabs == [a])
        #expect(model[group: first]?.active == a)
    }

    @Test func refusesTheSplitCommandWithFewerThanTwoTabs() {
        var model = LayoutModel()
        let didSplitEmpty = model.splitMovingActiveTab(.vertical, in: size)
        #expect(!didSplitEmpty)
        model.open(Tab(kind: "demo.hello", title: "a"))
        let didSplitOne = model.splitMovingActiveTab(.vertical, in: size)
        #expect(!didSplitOne)
        #expect(model.tree.groups.count == 1)
    }

    @Test func refusesASplitThatWouldBreakTheMinimumSize() {
        var model = LayoutModel()

        let didSplit = model.split(.vertical, in: CGSize(width: 500, height: 500))
        #expect(!didSplit)
        #expect(model.tree.groups.count == 1)
    }

    @Test func closingTheLastTabClosesTheGroupExceptTheLastOne() {
        var model = LayoutModel()
        let first = model.activeGroup
        let tab = Tab(kind: "demo.hello", title: "a")
        model.open(tab)
        _ = model.split(.vertical, in: size)
        let second = model.activeGroup
        let other = Tab(kind: "demo.hello", title: "b")
        model.open(other)

        model.close(other.id)
        #expect(model.tree == .group(first))
        #expect(model.activeGroup == first)
        #expect(model[group: second] == nil)

        model.close(tab.id)
        #expect(model.tree == .group(first))
        #expect(model.active.isEmpty)
    }

    @Test func movesTheActiveTabToTheNeighbor() {
        var model = LayoutModel()
        let first = model.activeGroup
        let tab = Tab(kind: "demo.hello", title: "a")
        model.open(tab)
        _ = model.split(.vertical, in: size)
        let second = model.activeGroup
        model = model.activating(first)

        let didMove = model.moveActiveTab(.right, in: size)
        #expect(didMove)

        // layout R12 then R10: the emptied source group closes.
        #expect(model.activeGroup == second)
        #expect(model.active.active == tab)
        #expect(model[group: first] == nil)
        #expect(model.tree == .group(second))

        let didMove2 = model.moveActiveTab(.right, in: size)
        #expect(!didMove2)
    }

    @Test func movingTheOnlyTabOutOfAGroupClosesIt() {
        var model = LayoutModel()
        let first = model.activeGroup
        model.open(Tab(kind: "demo.hello", title: "a"))
        _ = model.split(.vertical, in: size)
        let second = model.activeGroup
        let tab = Tab(kind: "demo.hello", title: "b")
        model.open(tab)

        let didMove = model.moveActiveTab(.left, in: size)
        #expect(didMove)

        #expect(model.tree == .group(first))
        #expect(model.activeGroup == first)
        #expect(model[group: second] == nil)
        #expect(model.active.active == tab)
    }

    @Test func focusMovesBetweenGroups() {
        var model = LayoutModel()
        let first = model.activeGroup
        _ = model.split(.vertical, in: size)
        let second = model.activeGroup

        let didFocus = model.focus(.left, in: size)
        #expect(didFocus)
        #expect(model.activeGroup == first)
        let didFocus2 = model.focus(.left, in: size)
        #expect(!didFocus2)
        let didFocus3 = model.focus(.right, in: size)
        #expect(didFocus3)
        #expect(model.activeGroup == second)
    }

    @Test func listsDirtyTabsInReadingOrderForConfirmation() {
        var model = LayoutModel()
        let clean = Tab(kind: "editor.file", title: "clean")
        let dirtyA = Tab(kind: "editor.file", title: "a", isDirty: true)
        model.open(dirtyA)
        model.open(clean)
        _ = model.split(.vertical, in: size)
        let dirtyB = Tab(kind: "editor.file", title: "b", isDirty: true)
        model.open(dirtyB)

        #expect(model.dirtyTabs() == [dirtyA, dirtyB])
        #expect(model.dirtyTabs(in: model.activeGroup) == [dirtyB])
    }
}
