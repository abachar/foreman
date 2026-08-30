import AppKit
import Foundation

/// layout R37: where each action of the registry sits in the Mac's menus.
///
/// The bar is **not** one submenu per feature namespace (that read as `Layout / Editor / Explorer /
/// Postgres / Git / Terminal / Browser / Run` and overflowed the bar, 2026-08-30): it is the menu
/// bar a Mac app is expected to have, and the features are placed into it by hand. This map is the
/// only place that knows the shape; everything it names comes from the registry (R22).
///
/// An action this map does not name has no menu entry — a shortcut is not a reason to be in a menu.
/// An action the map names but no feature registered is dropped, so a window without a repo has no
/// *Git* submenu.
nonisolated enum MenuBarLayout {
    indirect enum Entry {
        /// An action of the registry; `title` overrides the one it registered under.
        case action(String, title: String? = nil)
        /// One entry for the same action written once per scope (`…sendToAgent`): the first id
        /// registered gives the shortcut, and the one in scope acts.
        case anyOf([String], title: String)
        /// Every action whose id starts with the prefix, in registration order (`agents.`).
        case actions(prefix: String)
        /// product R8: the workspaces opened before; the app, not the registry, provides them.
        case recentFolders(String)
        case submenu(String, [Entry])
        case separator
    }

    /// A menu of the bar. `isStandard` marks the ones macOS already puts there: its entries are
    /// appended to the existing menu instead of creating a second one.
    struct Menu {
        let title: String
        let isStandard: Bool
        let entries: [Entry]
    }

    static let menus: [Menu] = [
        Menu(
            title: "File", isStandard: true,
            entries: [
                .recentFolders("Open Recent"),
                .separator,
                .action("editor.quickOpen", title: "Quick Open…"),
                .separator,
                .action("editor.save"),
                .action("editor.saveAll"),
                .separator,
                .action("layout.tab.close"),
            ]),
        Menu(
            title: "Edit", isStandard: true,
            entries: [
                .action("editor.find"),
                .action("editor.replace", title: "Find and Replace…"),
                .action("editor.search", title: "Find in Project…"),
                .action("editor.goToLine", title: "Go to Line…"),
                .separator,
                .action("editor.comment"),
                .action("postgres.comment"),
                .action("editor.indent"),
                .action("editor.outdent"),
                .action("editor.moveLine.up"),
                .action("editor.moveLine.down"),
                .separator,
                .action("editor.format"),
                .action("editor.fold"),
                .action("editor.unfold"),
            ]),
        Menu(
            title: "View", isStandard: true,
            entries: [
                .action("explorer.tree", title: "Explorer"),
                .action("layout.toolbar.toggle"),
                .action("editor.togglePreview"),
                .separator,
                .submenu(
                    "Tabs",
                    [
                        .action("layout.tab.previous"),
                        .action("layout.tab.next"),
                        .separator,
                        .actions(prefix: "layout.tab."),
                    ]),
                .submenu("Split", [.action("layout.split.vertical"), .action("layout.split.horizontal")]),
                .submenu(
                    "Focus Group",
                    [
                        .action("layout.focus.left", title: "Left"), .action("layout.focus.right", title: "Right"),
                        .action("layout.focus.up", title: "Above"), .action("layout.focus.down", title: "Below"),
                    ]),
                .submenu(
                    "Move Tab",
                    [
                        .action("layout.move.left", title: "Left"), .action("layout.move.right", title: "Right"),
                        .action("layout.move.up", title: "Up"), .action("layout.move.down", title: "Down"),
                    ]),
                .action("layout.focus.center"),
                .separator,
                .action("terminal.zoomIn"),
                .action("terminal.zoomOut"),
            ]),
        Menu(
            title: "Tools", isStandard: false,
            entries: [
                .submenu("Agents", [.actions(prefix: "agents.")]),
                .anyOf(
                    [
                        "editor.sendToAgent", "explorer.sendToAgent", "git.sendToAgent", "browser.sendToAgent",
                    ], title: "Send to Agent"),
                .separator,
                .submenu("Git", [.action("git.changes"), .action("git.history")]),
                .submenu(
                    "Postgres",
                    [
                        .action("postgres.schema"), .action("postgres.query"),
                        .action("postgres.history", title: "Query History…"),
                    ]),
                .submenu(
                    "Browser",
                    [
                        .action("browser.open", title: "Open Browser"), .action("browser.reload"),
                        .action("browser.back"), .action("browser.forward"),
                    ]),
            ]),
        Menu(
            title: "Run", isStandard: false,
            entries: [
                .action("run.palette", title: "Run Command…"),
                .separator,
                .action("run.stop"),
                .action("terminal.clear"),
            ]),
    ]
}

/// layout R37: the bar as the registry fills the map in, before any AppKit object exists.
nonisolated struct MenuBarModel: Equatable {
    struct Item: Equatable {
        /// The actions this entry stands for; more than one only for `anyOf` (R37).
        let ids: [String]
        let title: String
        /// `nil` for an action no shortcut reaches: a menu offers it all the same.
        let shortcut: Shortcut?
    }

    indirect enum Entry: Equatable {
        case item(Item)
        case submenu(String, [Entry])
        /// product R8: a submenu of folders, filled by the app when the menu is built.
        case recentFolders(String)
        case separator
    }

    struct Menu: Equatable {
        let title: String
        let isStandard: Bool
        let entries: [Entry]
    }

    let menus: [Menu]

    init(actions: [ShortcutAction], shortcut: (String) -> Shortcut?) {
        // What the map placed already, over the whole bar: `Close Tab` belongs to *File*, so the
        // `layout.tab.` family of *View ▸ Tabs* must not pick it up a second time.
        var placed: Set<String> = []
        menus = MenuBarLayout.menus.compactMap { menu in
            let entries = Self.resolve(menu.entries, actions: actions, shortcut: shortcut, placed: &placed)
            guard !entries.isEmpty else { return nil }
            return Menu(title: menu.title, isStandard: menu.isStandard, entries: entries)
        }
    }

    /// Drops what no feature registered, then the submenus and separators left with nothing to
    /// separate — a window without Postgres shows no empty *Postgres* submenu.
    private static func resolve(
        _ entries: [MenuBarLayout.Entry], actions: [ShortcutAction], shortcut: (String) -> Shortcut?,
        placed: inout Set<String>
    ) -> [Entry] {
        var resolved: [Entry] = []
        for entry in entries {
            switch entry {
            case .action(let id, let title):
                guard let action = actions.first(where: { $0.id == id }) else { continue }
                placed.insert(id)
                resolved.append(.item(Item(ids: [id], title: title ?? action.title, shortcut: shortcut(id))))
            case .anyOf(let ids, let title):
                let known = ids.filter { id in actions.contains { $0.id == id } }
                guard !known.isEmpty else { continue }
                placed.formUnion(known)
                resolved.append(.item(Item(ids: known, title: title, shortcut: known.compactMap(shortcut).first)))
            case .actions(let prefix):
                for action in actions where action.id.hasPrefix(prefix) && !placed.contains(action.id) {
                    placed.insert(action.id)
                    resolved.append(
                        .item(Item(ids: [action.id], title: action.title, shortcut: shortcut(action.id))))
                }
            case .submenu(let title, let children):
                let children = resolve(children, actions: actions, shortcut: shortcut, placed: &placed)
                guard !children.isEmpty else { continue }
                resolved.append(.submenu(title, children))
            case .recentFolders(let title):
                resolved.append(.recentFolders(title))
            case .separator:
                guard !resolved.isEmpty, resolved.last != .separator else { continue }
                resolved.append(.separator)
            }
        }
        while resolved.last == .separator {
            resolved.removeLast()
        }
        return resolved
    }
}

/// layout R37: the app's menu bar, rebuilt from the registry of the key window.
///
/// The actions belong to a window and the bar belongs to the app, so the bar follows the key
/// window. Key equivalents are **shown, never bound**: the registry's monitor is called before the
/// main menu's `performKeyEquivalent:` and swallows the event (checked 2026-08-30), and an item out
/// of scope is disabled, so no action can fire twice.
@MainActor
final class MenuBarController: NSObject, NSMenuItemValidation {
    private struct Window {
        weak var window: NSWindow?
        let shortcuts: ShortcutRegistry
    }

    /// product R8: the recent workspaces and what to do with one; the app owns both.
    var recentFolders: () -> [URL] = { [] }
    var openFolder: (URL) -> Void = { _ in }

    private var windows: [Window] = []
    private var observers: [any NSObjectProtocol] = []
    /// What this controller put into the bar, so it can take exactly that back out.
    ///
    /// Not an `identifier` on the items: `NSMenuItem.separator()` drops the one it is given, and
    /// the untagged separators piled up at every rebuild.
    private var inserted: [(menu: NSMenu, item: NSMenuItem)] = []

    override init() {
        super.init()
        // SwiftUI owns *File*, *Edit* and *View* and rebuilds them when the scene updates, taking
        // our entries with it (seen 2026-08-30). Putting them back as the menu opens is what makes
        // them survive; the bar is small enough that building it again costs nothing.
        for name in [
            NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification, NSMenu.didBeginTrackingNotification,
        ] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.rebuild() }
                })
        }
    }

    isolated deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// The window's actions; called once the window exists (layout R22: the registry is per window).
    func use(_ shortcuts: ShortcutRegistry, for window: NSWindow) {
        windows.removeAll { $0.window == nil || $0.window === window }
        windows.append(Window(window: window, shortcuts: shortcuts))
        rebuild()
    }

    /// Rebuilds from the key window, and again whenever its registry changes — a feature
    /// registering late (layout R36) reaches the menus too.
    func rebuild() {
        windows.removeAll { $0.window == nil }
        guard let shortcuts = keyWindowShortcuts else {
            apply(nil, shortcuts: nil)
            return
        }
        let model = withObservationTracking {
            MenuBarModel(actions: shortcuts.actions, shortcut: { shortcuts.shortcut(for: $0) })
        } onChange: { [weak self] in
            Task { @MainActor in self?.rebuild() }
        }
        apply(model, shortcuts: shortcuts)
    }

    private var keyWindowShortcuts: ShortcutRegistry? {
        windows.first { $0.window?.isKeyWindow == true }?.shortcuts ?? windows.last?.shortcuts
    }

    /// layout R37: an item is offered only while its action is in scope, exactly as the monitor
    /// resolves it — a disabled item cannot fire its key equivalent either.
    ///
    /// An action with no shortcut has no scope to check: the menu is the only way to reach it.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.representedObject as? MenuAction, let shortcuts = keyWindowShortcuts else {
            return true
        }
        // An entry standing for several scopes is offered as soon as one of them can act.
        return action.ids.contains { shortcuts.shortcut(for: $0) == nil || shortcuts.isAvailable($0) }
    }

    @objc private func performItem(_ sender: NSMenuItem) {
        (sender.representedObject as? MenuAction)?.perform()
    }

    // MARK: - AppKit

    private func apply(_ model: MenuBarModel?, shortcuts: ShortcutRegistry?) {
        guard let bar = NSApp.mainMenu else { return }
        for (menu, item) in inserted where menu.index(of: item) >= 0 {
            menu.removeItem(item)
        }
        inserted = []
        guard let model, let shortcuts else { return }
        // Foreman's own menus go before *Window*, where a Mac app puts them.
        var index = bar.items.firstIndex { $0.submenu?.title == "Window" } ?? bar.items.count
        for menu in model.menus {
            guard let standard = bar.items.first(where: { $0.submenu?.title == menu.title })?.submenu else {
                let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
                item.submenu = self.menu(named: menu.title, menu.entries, shortcuts: shortcuts)
                bar.insertItem(item, at: index)
                inserted.append((bar, item))
                index += 1
                continue
            }
            // A standard menu keeps what macOS put in it; ours is appended under a separator.
            for item in [NSMenuItem.separator()] + items(for: menu.entries, shortcuts: shortcuts) {
                standard.addItem(item)
                inserted.append((standard, item))
            }
        }
    }

    /// product R8: the folders opened before, most recent first, named by their folder.
    private func recentMenu(named title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        for folder in recentFolders() {
            let item = NSMenuItem(title: folder.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.toolTip = folder.path(percentEncoded: false)
            item.representedObject = folder as NSURL
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? NSURL else { return }
        openFolder(folder as URL)
    }

    private func menu(named title: String, _ entries: [MenuBarModel.Entry], shortcuts: ShortcutRegistry) -> NSMenu {
        let menu = NSMenu(title: title)
        for item in items(for: entries, shortcuts: shortcuts) {
            menu.addItem(item)
        }
        return menu
    }

    private func items(for entries: [MenuBarModel.Entry], shortcuts: ShortcutRegistry) -> [NSMenuItem] {
        entries.map { entry in
            let item: NSMenuItem
            switch entry {
            case .separator:
                item = .separator()
            case .submenu(let title, let children):
                item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = menu(named: title, children, shortcuts: shortcuts)
            case .recentFolders(let title):
                item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = recentMenu(named: title)
                item.isEnabled = !recentFolders().isEmpty
            case .item(let entry):
                let equivalent = entry.shortcut?.keyEquivalent
                item = NSMenuItem(
                    title: entry.title, action: #selector(performItem(_:)), keyEquivalent: equivalent?.key ?? "")
                item.keyEquivalentModifierMask = equivalent?.modifiers ?? []
                item.target = self
                item.representedObject = MenuAction(ids: entry.ids) { [weak shortcuts] in
                    guard let shortcuts else { return }
                    let id = entry.ids.first { shortcuts.isAvailable($0) } ?? entry.ids[0]
                    shortcuts.actions.first { $0.id == id }?.perform()
                }
            }
            return item
        }
    }
}

/// What a generated menu item stands for: the action's id, to validate it, and how to run it.
private final class MenuAction {
    let ids: [String]
    let perform: () -> Void

    init(ids: [String], perform: @escaping () -> Void) {
        self.ids = ids
        self.perform = perform
    }
}
