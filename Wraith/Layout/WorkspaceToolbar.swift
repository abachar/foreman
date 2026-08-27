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
    private let toolbar = NSToolbar(identifier: "dev.crafters.wraith.toolbar.\(UUID().uuidString)")
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
        let tokens = theme.tokens
        for item in toolbar.items.flatMap({ ($0 as? NSToolbarItemGroup)?.subitems ?? [$0] }) {
            guard let descriptor = layout.toolbarItem(item.itemIdentifier.rawValue),
                let button = item.view as? ToolbarButton ?? item.view?.subviews.first as? ToolbarButton
            else { continue }
            button.tokens = tokens
            button.font = theme.interfaceFont()
            button.image = image(descriptor.icon, badge: layout.badge(of: descriptor.id))
            // design R15: a toggle whose panel is visible is outlined.
            button.isOutlined = LayoutManager.panelID(ofToggle: descriptor.id).map(layout.panels.isVisible) ?? false
            button.fit()
        }
    }

    /// The trailing panel toggles travel as one group (design R15: a tight trio after Run).
    static let trailingTogglesID = "layout.panels.trailing"
    /// The room between Run and the trio: twice the room inside the trio (author, 2026-08-28),
    /// laid as a leading inset of the trio's first toggle.
    private static let trailingGap: CGFloat = 8

    private var identifiers: [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = []
        for id in Self.order(layout.toolbarItems.map { ($0.id, $0.placement) }) {
            if trailingToggleIDs.contains(id) {
                if identifiers.last?.rawValue != Self.trailingTogglesID {
                    identifiers.append(NSToolbarItem.Identifier(Self.trailingTogglesID))
                }
            } else {
                identifiers.append(NSToolbarItem.Identifier(id))
            }
        }
        return identifiers
    }

    private var trailingToggleIDs: [String] {
        layout.toolbarItems.filter { $0.placement == .trailing && LayoutManager.panelID(ofToggle: $0.id) != nil }
            .map(\.id)
    }

    /// layout R30: leading, a space, centre, a space, trailing — the features' items first in
    /// each placement, the layout's panel toggles after them (so Run precedes the right toggles).
    nonisolated static func order(_ items: [(id: String, placement: ToolbarItemDescriptor.Placement)]) -> [String] {
        func ids(_ placement: ToolbarItemDescriptor.Placement) -> [String] {
            let own = items.filter { $0.placement == placement }.map(\.id)
            return own.filter { LayoutManager.panelID(ofToggle: $0) == nil }
                + own.filter { LayoutManager.panelID(ofToggle: $0) != nil }
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
        if identifier.rawValue == Self.trailingTogglesID {
            let group = NSToolbarItemGroup(itemIdentifier: identifier)
            group.subitems = trailingToggleIDs.enumerated().compactMap { index, id in
                makeItem(NSToolbarItem.Identifier(id), leadingInset: index == 0 ? Self.trailingGap : 0)
            }
            group.isBordered = false
            return group
        }
        return makeItem(identifier)
    }

    private func makeItem(_ identifier: NSToolbarItem.Identifier, leadingInset: CGFloat = 0) -> NSToolbarItem? {
        guard let descriptor = layout.toolbarItem(identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        let button = ToolbarButton()
        button.identifier = NSUserInterfaceItemIdentifier(descriptor.id)
        // A panel toggle is an icon alone (design R15, the mockups); the others carry their name.
        button.title = LayoutManager.panelID(ofToggle: descriptor.id) == nil ? descriptor.title : ""
        button.tokens = theme.tokens
        button.font = theme.interfaceFont()
        button.image = image(descriptor.icon, badge: layout.badge(of: descriptor.id))
        button.target = self
        button.action = #selector(performButton(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.fit()
        item.view = leadingInset > 0 ? Self.inset(button, leading: leadingInset) : button
        item.label = descriptor.title
        item.toolTip = descriptor.title
        item.isBordered = false
        return item
    }

    /// `button` in a container `leading` points wider, pinned to its right edge.
    private static func inset(_ button: ToolbarButton, leading: CGFloat) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leading),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
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
            let item = NSMenuItem(title: entry.title, action: #selector(performEntry(_:)), keyEquivalent: "")
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
        guard let base = IconImage.resolve(icon) else { return nil }
        guard case .dot(let color) = badge else { return base }
        let tint = theme.tokens.textPrimary.nsColor
        let dot = theme.tokens.status(color).nsColor
        let size = NSSize(width: base.size.width + 4, height: base.size.height + 4)
        let image = NSImage(size: size, flipped: false) { rect in
            let tinted = base.copy() as? NSImage ?? base
            tinted.isTemplate = false
            tinted.lockFocus()
            tint.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: 0, y: 0, width: base.size.width, height: base.size.height))
            dot.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 7, y: rect.maxY - 7, width: 6, height: 6)).fill()
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
