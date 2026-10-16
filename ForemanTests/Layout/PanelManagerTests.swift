import Foundation
import SwiftUI
import Testing

@testable import Foreman

/// Panels: one per slot, toggle and replacement, lazy views, activation (layout R2–R6).
@MainActor
struct PanelManagerTests {
    private final class Probe {
        var built = 0
        var activations: [String] = []
    }

    private let probe = Probe()
    private let manager = PanelManager()

    private func panel(_ id: PanelID, side: PanelSide, order: Int = 0) -> PanelDescriptor {
        PanelDescriptor(
            id: id,
            title: id.rawValue,
            side: side,
            order: order,
            makeView: { [probe] in
                probe.built += 1
                return AnyView(EmptyView())
            },
            activate: { [probe] in probe.activations.append("+\(id.rawValue)") },
            deactivate: { [probe] in probe.activations.append("-\(id.rawValue)") }
        )
    }

    /// layout R36: a withdrawn panel is hidden, deactivated and forgotten, its view included.
    @Test func unregisterHidesAndForgetsThePanel() {
        manager.register(panel("git.status", side: .right))
        manager.toggle("git.status")
        _ = manager.view(for: "git.status")

        manager.unregister("git.status")
        #expect(manager.visible.isEmpty)
        #expect(manager.focus == .center)
        #expect(probe.activations == ["+git.status", "-git.status"])
        #expect(manager["git.status"] == nil)
        #expect(manager.view(for: "git.status") == nil)

        manager.register(panel("git.status", side: .right))
        _ = manager.view(for: "git.status")
        #expect(probe.built == 2)
    }

    /// layout R36: a panel registered after the restoration takes its slot, unless it was filled since.
    @Test func lateRegistrationTakesItsRestoredSlot() {
        manager.register(panel("pg.schema", side: .right))
        manager.restore(visible: [.right: "git.status", .left: "explorer"])
        #expect(manager.visible.isEmpty)
        manager.activateVisible()

        manager.register(panel("git.status", side: .right))
        #expect(manager.visible == [.right: "git.status"])
        #expect(probe.activations == ["+git.status"])

        manager.toggle("pg.schema")
        manager.unregister("git.status")
        manager.register(panel("git.status", side: .right))
        #expect(manager.visible == [.right: "pg.schema"])
    }

    @Test func sameShortcutTwiceShowsThenHides() {
        manager.register(panel("git.status", side: .left))

        manager.toggle("git.status")
        #expect(manager.visible == [.left: "git.status"])
        #expect(manager.focus == .panel("git.status"))

        manager.toggle("git.status")
        #expect(manager.visible.isEmpty)
        #expect(manager.focus == .center)
        #expect(probe.activations == ["+git.status", "-git.status"])
    }

    @Test func anotherPanelOfTheSameSlotReplacesTheVisibleOne() {
        manager.register(panel("explorer.tree", side: .left))
        manager.register(panel("git.status", side: .left))
        manager.register(panel("pg.schema", side: .right))

        manager.toggle("explorer.tree")
        manager.toggle("git.status")
        manager.toggle("pg.schema")

        #expect(manager.visible == [.left: "git.status", .right: "pg.schema"])
        #expect(probe.activations == ["+explorer.tree", "-explorer.tree", "+git.status", "+pg.schema"])
    }

    @Test func buildsTheViewOnceAndKeepsIt() {
        manager.register(panel("git.status", side: .left))

        #expect(manager.view(for: "git.status") != nil)
        #expect(manager.view(for: "git.status") != nil)
        manager.toggle("git.status")
        manager.toggle("git.status")
        #expect(manager.view(for: "git.status") != nil)

        #expect(probe.built == 1)
        #expect(manager.view(for: "unknown") == nil)
    }

    @Test func escapeReturnsFocusWithoutHiding() {
        manager.register(panel("git.status", side: .left))
        manager.toggle("git.status")

        manager.focusCenter()

        #expect(manager.focus == .center)
        #expect(manager.visible == [.left: "git.status"])
    }

    @Test func refusesADuplicatedID() {
        #expect(manager.register(panel("git.status", side: .left)))
        #expect(!manager.register(panel("git.status", side: .right)))
        #expect(manager.panels.count == 1)
    }

    @Test func restoreIgnoresAPanelThatChangedSlotAndActivatesLater() {
        manager.register(panel("git.status", side: .left))
        manager.register(panel("pg.schema", side: .right))

        manager.restore(visible: [.left: "git.status", .bottom: "pg.schema", .right: "gone"])
        #expect(manager.visible == [.left: "git.status"])
        #expect(probe.activations.isEmpty)
        #expect(manager.focus == .center)

        manager.activateVisible()
        #expect(probe.activations == ["+git.status"])
    }

    /// layout R2 (amended 2026-10-16): a slot's header lists its panels by order, then by
    /// registration — a conditional feature registering late still lands in its place.
    @Test func panelsOfASideFollowTheirOrderThenRegistration() {
        manager.register(panel("editor.search", side: .bottom, order: 1))
        manager.register(panel("explorer.tree", side: .left, order: 0))
        manager.register(panel("run.output", side: .bottom, order: 1))
        manager.register(panel("git.history", side: .bottom, order: 0))
        manager.register(panel("git.changes", side: .left, order: 1))

        #expect(manager.panels(on: .bottom).map(\.id) == ["git.history", "editor.search", "run.output"])
        #expect(manager.panels(on: .left).map(\.id) == ["explorer.tree", "git.changes"])
        #expect(manager.panels(on: .right).isEmpty)
    }

    /// layout R3 (amended 2026-10-16): a tab click shows its panel in place of the other, which
    /// keeps its view (R5) and is only deactivated (R4).
    @Test func aTabClickReplacesAndTheHiddenPanelKeepsItsView() {
        manager.register(panel("explorer.tree", side: .left))
        manager.register(panel("git.changes", side: .left, order: 1))
        manager.show("explorer.tree")
        _ = manager.view(for: "explorer.tree")

        manager.show("git.changes")
        _ = manager.view(for: "git.changes")
        manager.show("explorer.tree")
        _ = manager.view(for: "explorer.tree")

        #expect(manager.visible == [.left: "explorer.tree"])
        #expect(probe.built == 2)
        #expect(
            probe.activations == ["+explorer.tree", "-explorer.tree", "+git.changes", "-git.changes", "+explorer.tree"])
    }

    /// layout, edge cases: `git.changes` was persisted in the right slot before it moved left; it
    /// comes back hidden, and the left slot keeps what was restored there.
    @Test func aPanelPersistedOnItsOldSideComesBackHidden() {
        manager.register(panel("explorer.tree", side: .left))
        manager.restore(visible: [.left: "explorer.tree", .right: "git.changes", .bottom: "git.history"])
        manager.activateVisible()

        manager.register(panel("git.changes", side: .left, order: 1))
        manager.register(panel("git.history", side: .bottom))

        #expect(manager.visible == [.left: "explorer.tree", .bottom: "git.history"])
    }

    /// layout (status bar, 2026-10-16): a slot toggle shows the slot's first panel until another
    /// was shown, then the last one; pressed again it hides the slot.
    @Test func aSlotToggleShowsTheLastPanelOrTheFirst() {
        manager.register(panel("editor.search", side: .bottom, order: 1))
        manager.register(panel("git.history", side: .bottom, order: 0))

        manager.toggle(PanelSide.bottom)
        #expect(manager.visible == [.bottom: "git.history"])
        manager.show("editor.search")
        manager.toggle(PanelSide.bottom)
        #expect(manager.visible.isEmpty)
        manager.toggle(PanelSide.bottom)
        #expect(manager.visible == [.bottom: "editor.search"])
        #expect(manager.last == [.bottom: "editor.search"])

        manager.toggle(PanelSide.right)
        #expect(manager.visible == [.bottom: "editor.search"])
        #expect(manager.panelToShow(on: .right) == nil)
    }

    /// layout R36: a withdrawn last panel gives the toggle back to the slot's first panel; a last
    /// panel restored on a side it left is ignored the same way.
    @Test func aWithdrawnOrMovedLastPanelFallsBackToTheFirst() {
        manager.register(panel("explorer.tree", side: .left))
        manager.register(panel("git.changes", side: .left, order: 1))
        manager.show("git.changes")
        manager.hide(.left)
        manager.unregister("git.changes")
        #expect(manager.panelToShow(on: .left) == "explorer.tree")

        manager.restore(visible: [:], last: [.right: "explorer.tree"])
        #expect(manager.panelToShow(on: .right) == nil)
    }
}
