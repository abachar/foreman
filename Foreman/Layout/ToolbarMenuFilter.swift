import AppKit

/// git R40, layout R30: the filter field on top of a filterable toolbar menu (`ToolbarMenu`).
///
/// An `NSSearchField` in a menu item: AppKit hands the menu's keystrokes to the field once it is
/// the first responder of the menu's window, so typing filters while the menu stays open.
@MainActor
final class ToolbarMenuFilter: NSObject, NSSearchFieldDelegate {
    /// A row of the menu as the filter reads it.
    nonisolated enum Row: Equatable, Sendable {
        case header
        case separator
        /// The texts an entry is found by: its title, its subtitle, its submenu's titles.
        case item([String])
    }

    let item = NSMenuItem()
    private let field = NSSearchField()
    private weak var menu: NSMenu?

    init(menu: NSMenu, placeholder: String) {
        self.menu = menu
        super.init()
        field.placeholderString = placeholder
        field.delegate = self
        field.sendsSearchStringImmediately = true
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 34))
        field.frame = NSRect(x: 10, y: 5, width: 340, height: 24)
        field.autoresizingMask = [.width]
        container.autoresizingMask = [.width]
        container.addSubview(field)
        item.view = container
    }

    /// The field takes the keyboard as soon as the menu tracks (it runs its own loop).
    func focus() {
        RunLoop.main.perform(inModes: [.eventTracking, .default]) { [weak self] in
            guard let self else { return }
            field.window?.makeFirstResponder(field)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let menu else { return }
        let items = menu.items.filter { $0 !== item }
        let shown = Self.visibility(of: items.map(Self.row), query: field.stringValue)
        for (menuItem, isShown) in zip(items, shown) where menuItem.isHidden == isShown {
            menuItem.isHidden = !isShown
        }
    }

    private static func row(_ item: NSMenuItem) -> Row {
        if item.isSeparatorItem { return .separator }
        if item.isSectionHeader { return .header }
        return .item([item.title, item.subtitle ?? ""] + (item.submenu?.items.map(\.title) ?? []))
    }

    /// What stays shown for `query`: every row when it is empty; otherwise the entries one of
    /// whose texts contains it (case and diacritics ignored), the headers that keep an entry under
    /// them, and no separator.
    nonisolated static func visibility(of rows: [Row], query: String) -> [Bool] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return rows.map { _ in true } }
        var shown = rows.map { row -> Bool in
            guard case .item(let texts) = row else { return false }
            return texts.contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        for (index, row) in rows.enumerated() where row == .header {
            let next = rows[(index + 1)...].firstIndex { $0 == .header || $0 == .separator } ?? rows.count
            shown[index] = shown[(index + 1)..<next].contains(true)
        }
        return shown
    }
}
