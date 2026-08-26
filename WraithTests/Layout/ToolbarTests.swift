import Foundation
import Testing

@testable import Wraith

/// Toolbar items as the layout keeps them (layout R30, R31).
@MainActor
struct ToolbarTests {
    private let layout = LayoutManager()

    private func item(_ id: String, _ placement: ToolbarItemDescriptor.Placement) -> ToolbarItemDescriptor {
        ToolbarItemDescriptor(
            id: id, title: id, icon: "circle", placement: placement, kind: .action(perform: {}, secondaryMenu: nil))
    }

    @Test func refusesADuplicatedID() {
        #expect(layout.register(toolbarItem: item("agent.claude", .leading)))
        #expect(!layout.register(toolbarItem: item("agent.claude", .trailing)))
        #expect(layout.toolbarItems.count == 1)
    }

    @Test func keepsRegistrationOrderWithinEachPlacement() {
        layout.register(toolbarItem: item("run.main", .trailing))
        layout.register(toolbarItem: item("agent.claude", .leading))
        layout.register(toolbarItem: item("agent.opencode", .leading))

        #expect(
            layout.toolbarItems.filter { $0.placement == .leading }.map(\.id) == ["agent.claude", "agent.opencode"])
        #expect(layout.toolbarItems.filter { $0.placement == .trailing }.map(\.id) == ["run.main"])
    }

    @Test func badgesBelongToTheirItem() {
        layout.register(toolbarItem: item("agent.claude", .leading))

        layout.setBadge(.dot(.green), on: "agent.claude")

        #expect(layout.badge(of: "agent.claude") == .dot(.green))
        #expect(layout.badge(of: "run.main") == .none)
    }

    @Test func toolbarToggleIsALayoutShortcut() {
        #expect(layout.isToolbarVisible)

        layout.shortcuts.resolve(Shortcut(parsing: "cmd+opt+t")!, activeTabKind: nil, isTerminalFocused: false)?
            .perform()

        #expect(!layout.isToolbarVisible)
    }
}
