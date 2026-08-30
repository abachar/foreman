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

    private func panel(_ id: PanelID, side: PanelSide) -> PanelDescriptor {
        PanelDescriptor(
            id: id,
            title: id.rawValue,
            side: side,
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

    /// layout R6: a click into a visible panel moves the keyboard there and the model follows it,
    /// or `escape` and the panel-scoped shortcuts would answer for the center (R22b, R23).
    @Test func focusFollowsAClickIntoAVisiblePanel() {
        manager.register(panel("explorer.tree", side: .left))
        manager.register(panel("git.status", side: .right))
        manager.toggle("explorer.tree")
        manager.focusCenter()

        manager.focusPanel("explorer.tree")
        #expect(manager.focus == .panel("explorer.tree"))

        // A panel of an empty slot, and one nobody registered, have no focus to take.
        manager.focusPanel("git.status")
        manager.focusPanel("nope")
        #expect(manager.focus == .panel("explorer.tree"))
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
}
