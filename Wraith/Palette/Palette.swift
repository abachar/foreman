import AppKit
import Observation
import SwiftUI

/// The shared fuzzy palette (architecture): one per window, shown over it, fed by a source.
///
/// Presented as a key `NSPanel` child of the window so typing goes to it and the window's
/// shortcut monitor stays out of the way; it closes on `escape`, on a choice, or when it loses
/// the key status.
@Observable
@MainActor
final class Palette {
    /// editor R17: at most this many rows.
    nonisolated static let limit = 50

    private(set) var query = ""
    private(set) var results = PaletteSource.Results(items: [])
    private(set) var selectedIndex = 0
    private(set) var source: PaletteSource?
    private var panel: NSPanel?
    private var resignObserver: (any NSObjectProtocol)?
    private var search: Task<Void, Never>?

    var isPresented: Bool {
        panel != nil
    }

    func present(_ source: PaletteSource, over window: NSWindow) {
        dismiss()
        self.source = source
        query = ""
        results = PaletteSource.Results(items: [])
        selectedIndex = 0
        let panel = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.onKey = { [weak self] key in
            guard let self else { return }
            switch key {
            case .up:
                move(by: -1)
            case .down:
                move(by: 1)
            case .return(let newGroup):
                select(newGroup: newGroup)
            case .secondary:
                selectSecondary()
            case .escape:
                dismiss()
            }
        }
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentViewController = NSHostingController(rootView: PaletteView(palette: self))
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        // `onAppear` runs before the panel is key and the hosted field exists only after a layout
        // pass: claim the field now, and again on the next turn of the run loop.
        Self.focusField(of: panel)
        // After the layout pass: the hosted content may have resized the panel.
        panel.setFrameTopLeftPoint(NSPoint(x: window.frame.midX - 310, y: window.frame.maxY - 60))
        DispatchQueue.main.async { [weak panel] in
            guard let panel else { return }
            Self.focusField(of: panel)
        }
        self.panel = panel
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        update(query: "")
    }

    private static func focusField(of panel: NSPanel) {
        panel.contentView?.layoutSubtreeIfNeeded()
        guard let field = textField(in: panel.contentView), panel.firstResponder !== field.currentEditor() else {
            return
        }
        panel.makeFirstResponder(field)
    }

    private static func textField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField { return field }
        for subview in view.subviews {
            if let field = textField(in: subview) { return field }
        }
        return nil
    }

    func dismiss() {
        search?.cancel()
        search = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        guard let panel else { return }
        self.panel = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        source = nil
    }

    func update(query: String) {
        self.query = query
        selectedIndex = 0
        search?.cancel()
        guard let source else { return }
        search = Task { [source] in
            let results = await source.results(query)
            guard !Task.isCancelled else { return }
            self.results = PaletteSource.Results(
                items: Array(results.items.prefix(Self.limit)),
                notice: results.notice
                    ?? (results.items.count > Self.limit ? "Showing the first \(Self.limit) results" : nil))
        }
    }

    func move(by offset: Int) {
        guard !results.items.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + results.items.count) % results.items.count
    }

    func select(_ index: Int? = nil, newGroup: Bool) {
        let index = index ?? selectedIndex
        guard let source, results.items.indices.contains(index) else { return }
        let item = results.items[index]
        dismiss()
        source.select(item, newGroup)
    }

    /// run R6: `opt+enter`.
    func selectSecondary() {
        guard let source, results.items.indices.contains(selectedIndex) else { return }
        guard let secondary = source.secondary else { return select(newGroup: false) }
        let item = results.items[selectedIndex]
        dismiss()
        secondary(item)
    }
}

/// The palette's window: arrows, return and escape are taken before the field editor sees them.
final class PalettePanel: NSPanel {
    nonisolated enum Key: Equatable, Sendable {
        case up
        case down
        case `return`(newGroup: Bool)
        /// `opt+return`.
        case secondary
        case escape
    }

    var onKey: (Key) -> Void = { _ in }

    /// `cmd` opens in a new group, `opt` is the secondary action (editor R17, run R6).
    nonisolated static func returnKey(_ flags: NSEvent.ModifierFlags) -> Key {
        flags.contains(.option) ? .secondary : .return(newGroup: flags.contains(.command))
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else { return super.sendEvent(event) }
        switch event.keyCode {
        case 126:
            onKey(.up)
        case 125:
            onKey(.down)
        case 36, 76:
            onKey(Self.returnKey(event.modifierFlags))
        case 53:
            onKey(.escape)
        default:
            super.sendEvent(event)
        }
    }
}
