import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Foreman

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

    @Test func ordersLeadingCentreTrailingWithThePanelTogglesLast() {
        let order = WorkspaceToolbar.order([
            ("run.main", .trailing), ("layout.panel.explorer.tree", .leading), ("agent.claude", .center),
            ("layout.panel.git.changes", .trailing), ("agent.pi", .center), ("layout.panel.postgres.schema", .trailing),
        ])
        #expect(
            order == [
                "layout.panel.explorer.tree", "NSToolbarFlexibleSpaceItem", "agent.claude", "agent.pi",
                "NSToolbarFlexibleSpaceItem", "run.main", "layout.panel.git.changes", "layout.panel.postgres.schema",
            ])
    }

    @Test func aLeftOrRightPanelDeclaresItsToggleAndABottomOneDoesNot() {
        layout.register(
            panel: PanelDescriptor(id: "explorer.tree", title: "Explorer", side: .left, icon: "folder") {
                AnyView(EmptyView())
            })
        layout.register(
            panel: PanelDescriptor(id: "editor.search", title: "Search", side: .bottom) { AnyView(EmptyView()) })
        let toggle = layout.toolbarItem(LayoutManager.toggleID(of: "explorer.tree"))
        #expect(toggle?.placement == .leading)
        #expect(toggle?.icon == "folder")
        #expect(layout.toolbarItem(LayoutManager.toggleID(of: "editor.search")) == nil)
        #expect(LayoutManager.panelID(ofToggle: "layout.panel.explorer.tree") == "explorer.tree")
        #expect(LayoutManager.panelID(ofToggle: "run.main") == nil)

        #expect(!layout.panels.isVisible("explorer.tree"))
        if case .action(let perform, _) = toggle?.kind {
            perform()
        }
        #expect(layout.panels.isVisible("explorer.tree"))
    }

    @Test func toolbarToggleIsALayoutShortcut() {
        #expect(layout.isToolbarVisible)

        layout.shortcuts.resolve(Shortcut(parsing: "cmd+opt+t")!, activeTabKind: nil, isTerminalFocused: false)?
            .perform()

        #expect(!layout.isToolbarVisible)
    }
}

/// Icons of toolbar items and home entries (layout R30, agents R3).
@MainActor
struct IconImageTests {
    @Test func resolvesSymbolsAssetsAndFilesOnly() throws {
        #expect(IconImage.resolve("sparkles") != nil)
        #expect(IconImage.resolve("agent-pi") != nil)
        #expect(IconImage.resolve("no-such-icon-42") == nil)
        #expect(IconImage.resolve("relative/path.svg") == nil)

        let file = FileManager.default.temporaryDirectory.appending(path: "IconImageTests-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: file) }
        try #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8"><rect width="8" height="8"/></svg>"#
            .write(to: file, atomically: true, encoding: .utf8)
        let image = try #require(IconImage.resolve(file.path(percentEncoded: false)))
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: IconImage.pointSize, height: IconImage.pointSize))
        #expect(IconImage.resolve("agent-pi")?.size.width == IconImage.pointSize)
    }
}
