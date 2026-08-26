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
    static let limit = 50

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
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentViewController = NSHostingController(rootView: PaletteView(palette: self))
        let frame = window.frame
        panel.setFrameOrigin(
            NSPoint(x: frame.midX - 310, y: frame.maxY - 420 - 60))
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        update(query: "")
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
}
