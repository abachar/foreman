import Foundation
import Testing

@testable import Wraith

/// Tabs inside one group (layout R13, R14, R23 `cmd+N`).
struct TabGroupTests {
    private let one = Tab(kind: "demo.hello", title: "one")
    private let two = Tab(kind: "demo.hello", title: "two")
    private let three = Tab(kind: "demo.hello", title: "three")

    @Test func insertsAfterTheActiveTabAndActivatesIt() {
        var group = TabGroup()
        group.insert(one)
        group.insert(three)
        group.activate(one.id)

        group.insert(two)

        #expect(group.tabs.map(\.title) == ["one", "two", "three"])
        #expect(group.active == two)
    }

    @Test func closingTheActiveTabActivatesItsLeftNeighbor() {
        var group = TabGroup()
        group.insert(one)
        group.insert(two)
        group.insert(three)

        group.remove(three.id)
        #expect(group.active == two)

        group.activate(one.id)
        group.remove(one.id)
        #expect(group.active == two)

        group.remove(two.id)
        #expect(group.isEmpty)
        #expect(group.active == nil)
    }

    @Test func closingAnInactiveTabKeepsTheActiveOne() {
        var group = TabGroup()
        group.insert(one)
        group.insert(two)

        group.remove(one.id)

        #expect(group.active == two)
    }

    @Test func activatesByNumberNineBeingTheLast() {
        var group = TabGroup()
        group.insert(one)
        group.insert(two)
        group.insert(three)

        group.activate(number: 1)
        #expect(group.active == one)
        group.activate(number: 9)
        #expect(group.active == three)
        group.activate(number: 2)
        #expect(group.active == two)
        group.activate(number: 5)
        #expect(group.active == two)
    }

    @Test func cyclesThroughTabs() {
        var group = TabGroup()
        group.insert(one)
        group.insert(two)

        group.activateNext()
        #expect(group.active == one)
        group.activatePrevious()
        #expect(group.active == two)
    }

    // MARK: - layout R35

    private func threeTabs() -> TabGroup {
        var group = TabGroup()
        group.insert(one)
        group.insert(two)
        group.insert(three)
        return group
    }

    @Test func closeOthersKeepsThePivotOnly() {
        #expect(threeTabs().tabs(toClose: .others, around: two.id).map(\.title) == ["one", "three"])
    }

    @Test func closeAllTakesEveryTabInBarOrder() {
        #expect(threeTabs().tabs(toClose: .all, around: two.id).map(\.title) == ["one", "two", "three"])
    }

    @Test func closeUnmodifiedSkipsDirtyTabsAndIncludesThePivot() {
        var group = threeTabs()
        group.update(one.id, title: "one", isDirty: true)
        #expect(group.tabs(toClose: .unmodified, around: two.id).map(\.title) == ["two", "three"])
    }

    @Test func closeLeftAndRightStopAtThePivot() {
        let group = threeTabs()
        #expect(group.tabs(toClose: .left, around: two.id).map(\.title) == ["one"])
        #expect(group.tabs(toClose: .right, around: two.id).map(\.title) == ["three"])
        #expect(group.tabs(toClose: .left, around: one.id).isEmpty)
        #expect(group.tabs(toClose: .right, around: three.id).isEmpty)
    }

    @Test func closeSelectionAroundAnUnknownTabIsEmpty() {
        #expect(threeTabs().tabs(toClose: .all, around: TabID()).isEmpty)
    }
}
