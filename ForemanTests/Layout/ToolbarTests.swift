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

    /// layout R30 (amended 2026-10-16): the project leads; on the right the agents come first and
    /// Run last, whatever registered first.
    @Test func ordersTheProjectFirstAndRunLast() {
        let order = WorkspaceToolbar.order([
            ("git.branch", .leading), ("run.toolbar", .trailing), ("browser.open", .trailing),
            ("agent.claude", .trailing), (WorkspaceToolbar.projectID, .leading), ("agent.pi", .trailing),
        ])
        #expect(
            order == [
                WorkspaceToolbar.projectID, "git.branch", "NSToolbarFlexibleSpaceItem", "NSToolbarFlexibleSpaceItem",
                "agent.claude", "agent.pi", "browser.open", "run.toolbar",
            ])
    }

    /// layout R30 (amended 2026-10-16): the panel toggles left the toolbar for the status bar.
    @Test func aPanelDeclaresNoToolbarItem() {
        layout.register(
            panel: PanelDescriptor(id: "explorer.tree", title: "Project", side: .left, icon: "folder") {
                AnyView(EmptyView())
            })
        #expect(layout.toolbarItems.isEmpty)
        #expect(layout.panels["explorer.tree"] != nil)
    }

    @Test func toolbarToggleIsALayoutShortcut() {
        #expect(layout.isToolbarVisible)

        layout.shortcuts.resolve(Shortcut(parsing: "cmd+opt+t")!, activeTabKind: nil, isTerminalFocused: false)?
            .perform()

        #expect(!layout.isToolbarVisible)
    }
}

/// The project and branch widgets (layout R30 amended 2026-10-16, M21 21.3).
@MainActor
struct ToolbarWidgetTests {
    @Test func theProjectMarkTakesTwoInitials() {
        #expect(ProjectWidget.initials(of: "orders-api") == "OA")
        #expect(ProjectWidget.initials(of: "foreman") == "FO")
        #expect(ProjectWidget.initials(of: "my_big project") == "MB")
        #expect(ProjectWidget.initials(of: "x") == "X")
        #expect(ProjectWidget.initials(of: "") == "")
    }

    @Test func theProjectMenuOpensRevealsAndListsTheRecents() {
        var opened: [URL] = []
        let recents = [URL(filePath: "/tmp/a/one"), URL(filePath: "/tmp/b/two")]
        let entries = ProjectWidget.entries(
            recents: recents, choose: {}, openRecent: { opened.append($0) }, reveal: {})
        #expect(entries.map(\.title) == ["Open…", "Open Recent", "Reveal in Finder"])
        #expect(entries[1].children.map(\.title) == ["one", "two"])
        #expect(entries[2].startsSection)
        entries[1].children[1].perform()
        #expect(opened == [recents[1]])
        #expect(!ProjectWidget.entries(recents: [], choose: {}, openRecent: { _ in }, reveal: {})[1].isEnabled)
    }

    @Test func theBranchWidgetNamesTheBranchAndCountsTheWorktrees() {
        #expect(GitBranchWidget.text(repo: nil, head: "main", worktrees: 2) == ("main", "2 worktrees"))
        #expect(GitBranchWidget.text(repo: nil, head: "main", worktrees: 1) == ("main", "1 worktree"))
        #expect(GitBranchWidget.text(repo: "api", head: "dev", worktrees: 0).title == "api / dev")
        #expect(GitBranchWidget.text(repo: "api", head: "dev", worktrees: 0).detail == nil)
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
