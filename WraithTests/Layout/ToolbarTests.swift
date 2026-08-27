import AppKit
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
