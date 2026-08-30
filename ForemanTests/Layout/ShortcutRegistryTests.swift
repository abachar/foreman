import AppKit
import Foundation
import Testing

@testable import Foreman

/// The shortcut table: scopes, conflicts, overrides, terminal priority (layout R22–R26, config R4).
@MainActor
struct ShortcutRegistryTests {
    private let registry = ShortcutRegistry()

    private func action(
        _ id: String, _ shortcut: String?, scope: ShortcutScope = .global, isLayout: Bool = false
    ) -> ShortcutAction {
        ShortcutAction(id: id, title: id, scope: scope, defaultShortcut: shortcut, isLayout: isLayout, perform: {})
    }

    private func resolve(_ text: String, kind: String? = nil, terminal: Bool = false) -> String? {
        guard let shortcut = Shortcut(parsing: text) else { return nil }
        return registry.resolve(shortcut, activeTabKind: kind, isTerminalFocused: terminal)?.id
    }

    @Test func bindsDefaultsAndReportsAConflict() {
        registry.register(action("git.status", "cmd+shift+g"))
        registry.register(action("git.history", "cmd+shift+h"))
        registry.register(action("pg.schema", "cmd+shift+g"))

        #expect(resolve("cmd+shift+h") == "git.history")
        #expect(resolve("cmd+shift+g") == nil)
        #expect(registry.problems == [.conflict(Shortcut(parsing: "cmd+shift+g")!, ids: ["git.status", "pg.schema"])])
    }

    /// layout R36: withdrawing an action frees its shortcut and clears its conflict.
    @Test func unregisterFreesTheShortcut() {
        registry.register(action("git.status", "cmd+shift+g"))
        registry.register(action("pg.schema", "cmd+shift+g"))
        #expect(resolve("cmd+shift+g") == nil)

        registry.unregister("pg.schema")
        #expect(resolve("cmd+shift+g") == "git.status")
        #expect(registry.problems.isEmpty)
    }

    @Test func overrideCreatesAndResolvesConflicts() {
        registry.register(action("git.status", "cmd+shift+g"))
        registry.register(action("git.history", "cmd+shift+h"))

        registry.apply(overrides: ["git.history": "cmd+shift+g"])
        #expect(resolve("cmd+shift+g") == nil)
        #expect(resolve("cmd+shift+h") == nil)
        #expect(registry.problems.count == 1)

        registry.apply(overrides: ["git.history": "cmd+shift+g", "git.status": "cmd+g"])
        #expect(resolve("cmd+shift+g") == "git.history")
        #expect(resolve("cmd+g") == "git.status")
        #expect(registry.problems.isEmpty)
    }

    @Test func tabScopeMasksGlobalOnlyWhenItsKindIsActive() {
        registry.register(action("git.status", "cmd+k"))
        registry.register(action("editor.format", "cmd+k", scope: .tab(kind: "editor.file")))

        #expect(registry.problems.isEmpty)
        #expect(resolve("cmd+k") == "git.status")
        #expect(resolve("cmd+k", kind: "agent.claude") == "git.status")
        #expect(resolve("cmd+k", kind: "editor.file") == "editor.format")
    }

    @Test func twoTabScopesConflictOnlyWithEachOther() {
        registry.register(action("editor.format", "cmd+k", scope: .tab(kind: "editor.file")))
        registry.register(action("sql.format", "cmd+k", scope: .tab(kind: "pg.query")))
        registry.register(action("sql.run", "cmd+k", scope: .tab(kind: "pg.query")))

        #expect(resolve("cmd+k", kind: "editor.file") == "editor.format")
        #expect(resolve("cmd+k", kind: "pg.query") == nil)
        #expect(registry.problems.count == 1)
    }

    @Test func aFeatureCannotTakeALayoutShortcutButTheUserCan() {
        registry.register(action("layout.split.vertical", "cmd+d", isLayout: true))
        registry.register(action("pg.schema", "cmd+d"))

        #expect(resolve("cmd+d") == "layout.split.vertical")
        #expect(registry.problems == [.reservedByLayout(Shortcut(parsing: "cmd+d")!, id: "pg.schema")])

        registry.apply(overrides: ["layout.split.vertical": "cmd+shift+v", "pg.schema": "cmd+d"])
        #expect(resolve("cmd+d") == "pg.schema")
        #expect(resolve("cmd+shift+v") == "layout.split.vertical")
        #expect(registry.problems.isEmpty)
    }

    /// audit L2: the banner must go when the user moves the action off the layout's key.
    @Test func anActionMovedElsewhereStopsBeingReportedAgainstTheLayout() {
        registry.register(action("layout.split.vertical", "cmd+d", isLayout: true))
        registry.register(action("pg.schema", "cmd+d"))
        #expect(registry.problems.count == 1)

        // Not swapped with the layout action — moved to a key of its own.
        registry.apply(overrides: ["pg.schema": "cmd+shift+p"])

        #expect(registry.problems.isEmpty)
        #expect(resolve("cmd+shift+p") == "pg.schema")
        #expect(resolve("cmd+d") == "layout.split.vertical")
    }

    /// An override that does not parse falls back on the default, which is still the layout's.
    @Test func anOverrideThatDoesNotParseLeavesTheDefaultReported() {
        registry.register(action("layout.split.vertical", "cmd+d", isLayout: true))
        registry.register(action("pg.schema", "cmd+d"))

        registry.apply(overrides: ["pg.schema": "not a shortcut"])

        #expect(registry.problems.contains(.reservedByLayout(Shortcut(parsing: "cmd+d")!, id: "pg.schema")))
        #expect(registry.problems.contains(.invalidOverride(id: "pg.schema", text: "not a shortcut")))
        #expect(resolve("cmd+d") == "layout.split.vertical")
    }

    /// layout R24: the two halves of an override fail apart, and the message names the right one.
    @Test func reportsAnOverrideThatDoesNotParseApartFromOneThatNamesNoAction() {
        registry.register(action("git.status", "cmd+shift+g"))

        registry.apply(overrides: ["git.status": "cmd+", "nope": "cmd+n"])

        #expect(resolve("cmd+shift+g") == "git.status")
        #expect(
            registry.problems == [.invalidOverride(id: "git.status", text: "cmd+"), .unknownAction(id: "nope")])
        #expect(
            registry.problems.map(\.description) == [
                "shortcuts.git.status = \"cmd+\" is not a valid shortcut.", "shortcuts.nope names no action.",
            ])
    }

    @Test func aFocusedTerminalKeepsEverythingButCommandShortcuts() {
        registry.register(action("layout.focus.center", "escape", isLayout: true))
        registry.register(action("git.status", "cmd+shift+g"))

        #expect(resolve("escape") == "layout.focus.center")
        #expect(resolve("escape", terminal: true) == nil)
        #expect(resolve("cmd+shift+g", terminal: true) == "git.status")
    }

    @Test func exposesTheBoundShortcutForDisplay() {
        registry.register(action("git.status", "cmd+shift+g"))
        registry.register(action("git.history", nil))

        #expect(registry.shortcut(for: "git.status")?.description == "cmd+shift+g")
        #expect(registry.shortcut(for: "git.history") == nil)
    }
    @Test func terminalScopeAppliesToAnyTerminalKindAndMasksGlobal() {
        registry.register(action("editor.keepOpen", "cmd+k", scope: .tab(kind: "editor.file")))
        registry.register(action("terminal.clear", "cmd+k", scope: .terminal))
        registry.register(action("app.other", "cmd+k"))

        #expect(registry.problems.isEmpty)
        #expect(resolve("cmd+k", kind: "agent.claude", terminal: true) == "terminal.clear")
        #expect(resolve("cmd+k", kind: "run.build", terminal: true) == "terminal.clear")
        #expect(resolve("cmd+k", kind: "editor.file") == "editor.keepOpen")
        #expect(resolve("cmd+k", kind: "git.diff") == "app.other")
    }

    @Test func terminalKeepsEverythingWithoutCommand() {
        registry.register(action("terminal.clear", "ctrl+l", scope: .terminal))

        #expect(resolve("ctrl+l", kind: "agent.claude", terminal: true) == nil)
    }

    // MARK: - layout R33

    @Test func documentationGroupsBoundActionsByFeatureInRegistrationOrder() {
        registry.register(action("git.changes", "cmd+shift+g"))
        registry.register(action("editor.quickOpen", "cmd+p"))
        registry.register(action("git.history", "cmd+shift+h"))
        registry.register(action("agents.claude", nil))

        let groups = registry.documentation
        #expect(groups.map { $0.feature } == ["git", "editor"])
        #expect(groups[0].rows.map { $0.id } == ["git.changes", "git.history"])
        #expect(groups[1].rows.map { $0.shortcut } == ["cmd+p"])
    }

    @Test func documentationFoldsFamiliesIntoOneRow() {
        for number in 1...3 {
            registry.register(
                ShortcutAction(id: "layout.tab.\(number)", title: "Tab \(number)", defaultShortcut: "cmd+\(number)") {})
        }
        registry.register(
            ShortcutAction(id: "layout.tab.previous", title: "Previous Tab", defaultShortcut: "cmd+shift+[") {})
        registry.register(ShortcutAction(id: "layout.tab.next", title: "Next Tab", defaultShortcut: "cmd+shift+]") {})
        for (direction, title) in [("left", "Left"), ("right", "Right"), ("up", "Above"), ("down", "Below")] {
            registry.register(
                ShortcutAction(
                    id: "layout.focus.\(direction)", title: "Focus Group \(title)",
                    defaultShortcut: "cmd+opt+\(direction)"
                ) {})
        }
        registry.register(ShortcutAction(id: "editor.moveLine.up", title: "Move Line Up", defaultShortcut: "opt+up") {})
        registry.register(
            ShortcutAction(id: "editor.moveLine.down", title: "Move Line Down", defaultShortcut: "opt+down") {})

        let rows = registry.documentation.flatMap(\.rows).map { "\($0.title) · \($0.shortcut)" }
        #expect(
            rows == [
                "Tab N · cmd+N", "Previous Tab · cmd+shift+[", "Next Tab · cmd+shift+]", "Focus Group · cmd+opt+←→↑↓",
                "Move Line · opt+↑↓",
            ])
    }
}

/// layout R22b, R23: the `panel` scope.
@MainActor
struct PanelScopeTests {
    @Test func panelScopedActionOnlyResolvesWhenAPanelHasFocus() throws {
        let layout = LayoutManager()
        let escape = try #require(Shortcut(parsing: "escape"))
        #expect(
            layout.shortcuts.resolve(escape, activeTabKind: nil, isTerminalFocused: false, isPanelFocused: true)?.id
                == "layout.focus.center")
        #expect(
            layout.shortcuts.resolve(
                escape, activeTabKind: "editor.file", isTerminalFocused: false, isPanelFocused: false) == nil)
        #expect(layout.shortcuts.problems.isEmpty)
    }
}

/// layout R37: the map from the registry to the Mac's menus.
@MainActor
struct MenuBarModelTests {
    private let registry = ShortcutRegistry()

    private func register(_ id: String, _ title: String, _ shortcut: String?, scope: ShortcutScope = .global) {
        registry.register(
            ShortcutAction(id: id, title: title, scope: scope, defaultShortcut: shortcut, perform: {}))
    }

    private func model() -> MenuBarModel {
        MenuBarModel(actions: registry.actions, shortcut: { registry.shortcut(for: $0) })
    }

    /// The tree as the user reads it: `Menu > Submenu > Item`, a separator as `-`.
    private func tree(_ model: MenuBarModel) -> [String] {
        model.menus.flatMap { menu in
            [menu.title + (menu.isStandard ? " (standard)" : "")] + rows(menu.entries, under: "  ")
        }
    }

    private func rows(_ entries: [MenuBarModel.Entry], under indent: String) -> [String] {
        entries.flatMap { entry -> [String] in
            switch entry {
            case .separator: return [indent + "-"]
            case .item(let item):
                return [indent + item.title + (item.shortcut.map { " · \($0)" } ?? "")]
            case .submenu(let title, let children):
                return [indent + title + " >"] + rows(children, under: indent + "  ")
            case .recentFolders(let title):
                return [indent + title + " > (recent folders)"]
            }
        }
    }

    /// `Close Tab` is a `layout.tab.` id but belongs to *File*: the family of *View* leaves it alone.
    @Test func placesEachActionWhereTheMapSaysAndNotUnderItsNamespace() {
        register("editor.save", "Save", "cmd+s")
        register("layout.tab.close", "Close Tab", "cmd+w")
        register("editor.quickOpen", "Quick Open", "cmd+p")

        #expect(
            tree(model()) == [
                "File (standard)", "  Open Recent > (recent folders)", "  -", "  Quick Open… · cmd+p", "  -",
                "  Save · cmd+s", "  -", "  Close Tab · cmd+w",
            ])
    }

    /// layout R38: *New File* leads *File*, where a Mac app puts it.
    @Test func newFileLeadsTheFileMenu() {
        register("editor.newFile", "New File", "cmd+n")
        register("editor.save", "Save", "cmd+s")

        #expect(
            tree(model()) == [
                "File (standard)", "  New File · cmd+n", "  -", "  Open Recent > (recent folders)", "  -",
                "  Save · cmd+s",
            ])
    }

    /// layout R37: a menu is a map, so an action with no shortcut belongs in it all the same.
    @Test func keepsAnActionNoShortcutReaches() {
        register("agents.claude", "Claude", nil)

        #expect(tree(model()).suffix(3) == ["Tools", "  Agents >", "    Claude"])
    }

    /// layout R37: the same action written once per scope is **one** entry.
    @Test func foldsAnActionWrittenOncePerScopeIntoOneEntry() {
        register("editor.sendToAgent", "Send to Agent", "cmd+e", scope: .tab(kind: "editor.file"))
        register("explorer.sendToAgent", "Send to Agent", "cmd+e", scope: .panel)

        #expect(tree(model()).suffix(2) == ["Tools", "  Send to Agent · cmd+e"])
    }

    @Test func leavesOutWhatTheMapDoesNotName() {
        register("editor.keepOpen", "Keep Open", "cmd+k", scope: .tab(kind: "editor.file"))

        // Only *File* is left, and only for its recent folders.
        #expect(tree(model()) == ["File (standard)", "  Open Recent > (recent folders)"])
    }

    @Test func dropsASubmenuNoFeatureRegistered() {
        register("git.changes", "Changes", "cmd+shift+g")
        register("browser.open", "Browser", "cmd+shift+o")

        // No Postgres in this window, and `git.history` is not registered either.
        #expect(
            tree(model()).suffix(5) == [
                "Tools", "  Git >", "    Changes · cmd+shift+g", "  Browser >", "    Open Browser · cmd+shift+o",
            ])
    }

    @Test func writesTheShortcutTheRegistryBoundAndTheTitleTheMapChose() {
        register("editor.search", "Search", "cmd+shift+f")
        registry.apply(overrides: ["editor.search": "cmd+opt+shift+f"])

        #expect(tree(model()).suffix(2) == ["Edit (standard)", "  Find in Project… · cmd+shift+opt+f"])
    }

    @Test func foldsTheFamiliesIntoSubmenusInsteadOfOneEntryEach() {
        register("layout.tab.previous", "Previous Tab", "cmd+shift+[")
        for number in 1...3 {
            register("layout.tab.\(number)", "Tab \(number)", "cmd+\(number)")
        }

        #expect(
            tree(model()).suffix(7) == [
                "View (standard)", "  Tabs >", "    Previous Tab · cmd+shift+[", "    -", "    Tab 1 · cmd+1",
                "    Tab 2 · cmd+2", "    Tab 3 · cmd+3",
            ])
    }

    /// layout R37: the menu offers exactly what the keyboard would do, so nothing fires out of scope.
    @Test func anItemIsAvailableOnlyWhereItsScopeIs() {
        register("editor.format", "Format File", "cmd+shift+l", scope: .tab(kind: "editor.file"))
        register("git.changes", "Changes", "cmd+shift+g")

        #expect(registry.isAvailable("git.changes"))
        // No window is monitoring, so there is no active tab: the scoped action is not offered.
        #expect(!registry.isAvailable("editor.format"))
        #expect(!registry.isAvailable("nope"))
    }
}

/// layout R37: what an `NSMenuItem` shows on its right.
struct ShortcutKeyEquivalentTests {
    private func equivalent(_ text: String) -> (key: String, modifiers: NSEvent.ModifierFlags) {
        Shortcut(parsing: text)!.keyEquivalent
    }

    @Test func writesTheLetterAndItsModifiers() {
        let (key, modifiers) = equivalent("cmd+shift+g")

        #expect(key == "g")
        #expect(modifiers == [.command, .shift])
    }

    @Test func writesEveryModifierName() {
        #expect(equivalent("cmd+opt+ctrl+shift+k").modifiers == [.command, .option, .control, .shift])
        #expect(equivalent("alt+k").modifiers == [.option])
    }

    @Test func turnsANamedKeyIntoTheCharacterAppKitDraws() {
        #expect(equivalent("escape").key == "\u{1B}")
        #expect(equivalent("cmd+delete").key == "\u{8}")
        #expect(equivalent("return").key == "\r")
        #expect(equivalent("cmd+opt+left").key == Shortcut.character(NSLeftArrowFunctionKey))
    }
}

/// layout, audit C2: what the window installs must not outlive the window.
///
/// The monitor's block is retained by AppKit until `removeMonitor`, and it holds the focus
/// context, whose captures reach the `LayoutManager`. Closing the window has to be what breaks
/// that chain — a `deinit` cannot, since it is the chain that keeps `deinit` from running.
@MainActor
struct ShortcutMonitorLifetimeTests {
    /// A window the test owns: `isReleasedWhenClosed` off, so closing it does not free it under
    /// ARC, and never ordered in, so the host app does not quit with its last window.
    static func window() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .closable],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func closingTheWindowReleasesEverythingTheMonitorHeld() {
        weak var released: LayoutManager?
        let window = Self.window()
        do {
            let layout = LayoutManager()
            released = layout
            // Captured strongly on purpose: the teardown must hold even for the worst caller.
            layout.shortcuts.startMonitoring(window: window) {
                (activeTabKind: layout.model.active.active?.kind, isTerminalFocused: false, isPanelFocused: false)
            }
        }
        #expect(released != nil, "the monitor holds the manager while the window is open")

        window.close()

        #expect(released == nil, "closing the window must release the layout graph")
    }

    @Test func stoppingTwiceIsANoOp() {
        let layout = LayoutManager()
        let window = Self.window()
        layout.shortcuts.startMonitoring(window: window) {
            (activeTabKind: nil, isTerminalFocused: false, isPanelFocused: false)
        }
        layout.shortcuts.stopMonitoring()
        layout.shortcuts.stopMonitoring()
        window.close()
    }
}
