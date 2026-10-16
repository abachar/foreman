import AppKit
import Foundation
import Observation

/// The native toolbar of a window (layout R30–R32), dressed as design R15 says (option A,
/// decision 2026-08-27): `unifiedCompact`, one flat `ToolbarButton` per item on the tokens.
///
/// Leading items, a flexible space, trailing items, in registration order; nothing of its own.
@MainActor
final class WorkspaceToolbar: NSObject, NSToolbarDelegate, NSMenuDelegate {
    private let layout: LayoutManager
    private let theme: ThemeService
    /// A unique identifier per window: toolbars sharing one form a "family" and AppKit replays
    /// every insertion on each member, which asserts as soon as two windows differ in items
    /// (bug: the second window crashed, 2026-08-27).
    private let toolbar = NSToolbar(identifier: "dev.crafters.foreman.toolbar.\(UUID().uuidString)")
    private var menuItemsByMenu: [ObjectIdentifier: String] = [:]

    init(layout: LayoutManager, theme: ThemeService) {
        self.layout = layout
        self.theme = theme
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
    }

    /// Installs the toolbar and keeps it in sync with the manager.
    func attach(to window: NSWindow) {
        window.toolbar = toolbar
        // design R4, R15: the thin bar; its ground is the window's (R14).
        window.toolbarStyle = .unifiedCompact
        sync()
    }

    /// The icons already built, keyed by the icon and its badge; dropped when the theme changes.
    ///
    /// `sync` runs on every SwiftUI update and used to resolve, tint and redraw every item's
    /// image each time — an SF Symbol lookup or a file read per item per update (audit M15).
    private var images: [String: NSImage] = [:]
    private var imagesTokens: ThemeService.Tokens?

    /// Items and visibility as the manager says; called on every SwiftUI update.
    func sync() {
        toolbar.isVisible = layout.isToolbarVisible
        if imagesTokens != theme.tokens {
            imagesTokens = theme.tokens
            images.removeAll()
        }
        let wanted = identifiers
        if toolbar.items.map(\.itemIdentifier) != wanted {
            while !toolbar.items.isEmpty {
                toolbar.removeItem(at: 0)
            }
            for (index, identifier) in wanted.enumerated() {
                toolbar.insertItem(withItemIdentifier: identifier, at: index)
            }
        }
        let tokens = theme.tokens
        for item in toolbar.items.flatMap({ ($0 as? NSToolbarItemGroup)?.subitems ?? [$0] }) {
            guard let descriptor = layout.toolbarItem(item.itemIdentifier.rawValue),
                let button = item.view as? ToolbarButton ?? item.view?.subviews.first as? ToolbarButton
            else { continue }
            button.tokens = tokens
            button.font = theme.interfaceFont()
            button.image = image(descriptor.icon, badge: layout.badge(of: descriptor.id))
            button.fit()
        }
    }

    private var identifiers: [NSToolbarItem.Identifier] {
        Self.order(layout.toolbarItems.map { ($0.id, $0.placement) }).map { NSToolbarItem.Identifier($0) }
    }

    /// layout R30: leading, a space, centre, a space, trailing, each in registration order; in
    /// the centre the agents come first, whatever the registration order (browser R1).
    nonisolated static func order(_ items: [(id: String, placement: ToolbarItemDescriptor.Placement)]) -> [String] {
        func ids(_ placement: ToolbarItemDescriptor.Placement) -> [String] {
            let own = items.filter { $0.placement == placement }.map(\.id)
            return own.filter { $0.hasPrefix("agent.") } + own.filter { !$0.hasPrefix("agent.") }
        }
        return ids(.leading) + [NSToolbarItem.Identifier.flexibleSpace.rawValue] + ids(.center)
            + [NSToolbarItem.Identifier.flexibleSpace.rawValue] + ids(.trailing)
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
        makeItem(identifier)
    }

    private func makeItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        guard let descriptor = layout.toolbarItem(identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        let button = ToolbarButton()
        button.identifier = NSUserInterfaceItemIdentifier(descriptor.id)
        button.title = descriptor.title
        button.tokens = theme.tokens
        button.font = theme.interfaceFont()
        button.image = image(descriptor.icon, badge: layout.badge(of: descriptor.id))
        button.target = self
        button.action = #selector(performButton(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.fit()
        item.view = button
        item.label = descriptor.title
        item.toolTip = descriptor.title
        item.isBordered = false
        return item
    }

    @objc private func performButton(_ sender: ToolbarButton) {
        guard let id = sender.identifier?.rawValue, let descriptor = layout.toolbarItem(id) else { return }
        let event = NSApp.currentEvent
        let isSecondary = event.map { $0.type == .rightMouseUp || $0.modifierFlags.contains(.control) } ?? false
        switch descriptor.kind {
        case .menu:
            popUp(menu(for: id), under: sender)
        case .action(let perform, let secondaryMenu):
            // layout R31: a right click (or control-click) opens the secondary menu instead.
            if isSecondary {
                if secondaryMenu != nil {
                    popUp(menu(for: id), under: sender)
                }
                return
            }
            perform()
        }
    }

    private func popUp(_ menu: NSMenu, under button: NSButton) {
        menuNeedsUpdate(menu)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
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
            // layout R37: the entry writes the shortcut of what it offers.
            let equivalent = entry.shortcut?.keyEquivalent
            let item = NSMenuItem(
                title: entry.title, action: #selector(performEntry(_:)), keyEquivalent: equivalent?.key ?? "")
            item.keyEquivalentModifierMask = equivalent?.modifiers ?? []
            item.target = self
            item.subtitle = entry.subtitle
            item.representedObject = Entry(perform: entry.perform)
            if case .dot(let color) = entry.badge {
                item.image = dot(color)
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

    /// The icon, with a colored dot in its corner when the item carries a badge (layout R31);
    /// design R15: the dot is a state token, the icon is tinted by the button.
    private func image(_ icon: String, badge: ToolbarBadge) -> NSImage? {
        let key = "\(icon)|\(badge)"
        if let cached = images[key] { return cached }
        guard let built = build(icon, badge: badge) else { return nil }
        images[key] = built
        return built
    }

    private func build(_ icon: String, badge: ToolbarBadge) -> NSImage? {
        guard let base = IconImage.resolve(icon) else { return nil }
        let color: ToolbarBadge.BadgeColor
        var count: Int?
        switch badge {
        case .none: return base
        case .dot(let dotColor): color = dotColor
        case .count(let number, let dotColor):
            color = dotColor
            count = number
        }
        let tint = theme.tokens.textPrimary.nsColor
        let dot = theme.tokens.status(color).nsColor
        let size = NSSize(width: base.size.width + 6, height: base.size.height + 6)
        let image = NSImage(size: size, flipped: false) { rect in
            let tinted = base.copy() as? NSImage ?? base
            tinted.isTemplate = false
            tinted.lockFocus()
            tint.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: 0, y: 0, width: base.size.width, height: base.size.height))
            dot.setFill()
            guard let count else {
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 7, y: rect.maxY - 7, width: 6, height: 6)).fill()
                return true
            }
            // agents R6: the number of agents running, in the dot.
            let disc = NSRect(x: rect.maxX - 11, y: rect.maxY - 11, width: 11, height: 11)
            NSBezierPath(ovalIn: disc).fill()
            let text = NSAttributedString(
                string: count > 9 ? "9+" : "\(count)",
                attributes: [.font: NSFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: NSColor.white])
            let textSize = text.size()
            text.draw(at: NSPoint(x: disc.midX - textSize.width / 2, y: disc.midY - textSize.height / 2))
            return true
        }
        image.isTemplate = false
        return image
    }

    private func dot(_ color: ToolbarBadge.BadgeColor) -> NSImage {
        let fill = theme.tokens.status(color).nsColor
        return NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}
