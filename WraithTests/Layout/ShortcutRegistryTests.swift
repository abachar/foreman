import Foundation
import Testing

@testable import Wraith

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

    @Test func reportsAnOverrideThatDoesNotParseOrNameAnAction() {
        registry.register(action("git.status", "cmd+shift+g"))

        registry.apply(overrides: ["git.status": "cmd+", "nope": "cmd+n"])

        #expect(resolve("cmd+shift+g") == "git.status")
        #expect(registry.problems.count == 2)
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
}
