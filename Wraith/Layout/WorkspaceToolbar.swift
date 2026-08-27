import AppKit
import Observation

/// The native toolbar of a window (layout R30–R32).
///
/// Leading items, a flexible space, trailing items, in registration order; nothing of its own.
@MainActor
final class WorkspaceToolbar: NSObject, NSToolbarDelegate, NSMenuDelegate {
    private let layout: LayoutManager
    private let toolbar = NSToolbar(identifier: "dev.crafters.wraith.toolbar")
    private var menuItemsByMenu: [ObjectIdentifier: String] = [:]

    init(layout: LayoutManager) {
        self.layout = layout
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
    }

    /// Installs the toolbar and keeps it in sync with the manager.
    func attach(to window: NSWindow) {
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        sync()
    }

    /// Items and visibility as the manager says; called on every SwiftUI update.
    func sync() {
        toolbar.isVisible = layout.isToolbarVisible
        let wanted = identifiers
        if toolbar.items.map(\.itemIdentifier) != wanted {
            while !toolbar.items.isEmpty {
                toolbar.removeItem(at: 0)
            }
            for (index, identifier) in wanted.enumerated() {
                toolbar.insertItem(withItemIdentifier: identifier, at: index)
            }
        }
        for item in toolbar.items {
            guard let descriptor = layout.toolbarItem(item.itemIdentifier.rawValue) else { continue }
            item.image = Self.image(descriptor.icon, badge: layout.badge(of: descriptor.id))
        }
    }

    private var identifiers: [NSToolbarItem.Identifier] {
        let leading = layout.toolbarItems.filter { $0.placement == .leading }.map { NSToolbarItem.Identifier($0.id) }
        let trailing = layout.toolbarItems.filter { $0.placement == .trailing }.map { NSToolbarItem.Identifier($0.id) }
        return leading + [.flexibleSpace] + trailing
    }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar: Bool
    ) -> NSToolbarItem? {
        guard let descriptor = layout.toolbarItem(identifier.rawValue) else { return nil }
        let item: NSToolbarItem
        switch descriptor.kind {
        case .action:
            item = NSToolbarItem(itemIdentifier: identifier)
            item.target = self
            item.action = #selector(performItem(_:))
        case .menu:
            let menuItem = NSMenuToolbarItem(itemIdentifier: identifier)
            menuItem.menu = menu(for: descriptor.id)
            menuItem.showsIndicator = true
            item = menuItem
        }
        item.label = descriptor.title
        item.toolTip = descriptor.title
        item.image = Self.image(descriptor.icon, badge: layout.badge(of: descriptor.id))
        item.isBordered = true
        return item
    }

    @objc private func performItem(_ sender: NSToolbarItem) {
        guard let descriptor = layout.toolbarItem(sender.itemIdentifier.rawValue),
            case .action(let perform, let secondaryMenu) = descriptor.kind
        else { return }
        // layout R31: a right click (or control-click) opens the secondary menu instead.
        if let event = NSApp.currentEvent, event.type == .rightMouseUp || event.modifierFlags.contains(.control),
            secondaryMenu != nil
        {
            let menu = menu(for: descriptor.id)
            menuNeedsUpdate(menu)
            if let view = sender.view {
                NSMenu.popUpContextMenu(menu, with: event, for: view)
            }
            return
        }
        perform()
    }

    // MARK: - Menus (built on demand, layout R30)

    private func menu(for id: String) -> NSMenu {
        let menu = NSMenu(title: id)
        menu.delegate = self
        menuItemsByMenu[ObjectIdentifier(menu)] = id
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let id = menuItemsByMenu[ObjectIdentifier(menu)], let descriptor = layout.toolbarItem(id) else { return }
        let entries: [ToolbarMenuEntry]
        switch descriptor.kind {
        case .menu(let provider):
            entries = provider()
        case .action(_, let secondaryMenu):
            entries = secondaryMenu?() ?? []
        }
        menu.removeAllItems()
        for entry in entries {
            let item = NSMenuItem(title: entry.title, action: #selector(performEntry(_:)), keyEquivalent: "")
            item.target = self
            item.subtitle = entry.subtitle
            item.representedObject = Entry(perform: entry.perform)
            if case .dot(let color) = entry.badge {
                item.image = Self.dot(color)
            }
            menu.addItem(item)
        }
    }

    @objc private func performEntry(_ sender: NSMenuItem) {
        (sender.representedObject as? Entry)?.perform()
    }

    private final class Entry {
        let perform: () -> Void

        init(perform: @escaping () -> Void) {
            self.perform = perform
        }
    }

    // MARK: - Images

    /// The icon, with a colored dot in its corner when the item carries a badge (layout R31).
    private static func image(_ icon: String, badge: ToolbarBadge) -> NSImage? {
        guard let base = IconImage.resolve(icon) else { return nil }
        guard case .dot(let color) = badge else { return base }
        let size = NSSize(width: base.size.width + 4, height: base.size.height + 4)
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: NSRect(x: 0, y: 0, width: base.size.width, height: base.size.height))
            nsColor(color).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 7, y: rect.maxY - 7, width: 6, height: 6)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func dot(_ color: ToolbarBadge.BadgeColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            nsColor(color).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        return image
    }

    private static func nsColor(_ color: ToolbarBadge.BadgeColor) -> NSColor {
        switch color {
        case .green: return .systemGreen
        case .orange: return .systemOrange
        case .red: return .systemRed
        }
    }
}
