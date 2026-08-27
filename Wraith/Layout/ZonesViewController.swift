import AppKit
import SwiftUI

/// The four zones as native split views (layout, options): `left | (center / bottom) | right`.
///
/// Panels are collapsible items with their minimum thickness; the center never goes under
/// 300 x 150 pt (R19). On resize the panels shrink then hide in the order right, left, bottom and
/// come back by themselves (R20), without touching the persisted sizes.
final class ZonesViewController: GutterSplitViewController {
    /// What the SwiftUI side asks for; applied on every update.
    struct Configuration {
        var visible: [PanelSide: PanelID]
        var sizes: [PanelSide: CGFloat]
        var focus: FocusTarget
        var center: AnyView
        var panelView: (PanelID) -> AnyView?
        var onPanelResized: (PanelSide, CGFloat) -> Void
        var onFirstFrame: () -> Void
        /// The window is known: the shortcut monitor can be installed (layout, options).
        var onWindow: (NSWindow) -> Void
        /// The user moved or resized the window (layout R27).
        var onWindowFrame: (CGRect) -> Void
        /// design R2, R14, R20: the gutter between the zones and the ground it shows.
        var gutter: CGFloat
        var windowBackground: NSColor
    }

    /// design R20: both split views draw their divider as the gutter; set before the views load.
    private let column: GutterSplitViewController = {
        let controller = GutterSplitViewController()
        controller.splitView = GutterSplitView()
        return controller
    }()
    private let slots: [PanelSide: SlotViewController] = [
        .left: SlotViewController(), .right: SlotViewController(), .bottom: SlotViewController(),
    ]
    private let center = NSHostingController(rootView: AnyView(EmptyView()))
    private var configuration: Configuration?
    private var isApplying = false
    private var hasShownFirstFrame = false
    private var frameObservations: [Task<Void, Never>] = []

    /// A controller given its own split view must hold its items before the view loads: an empty
    /// one asserts in `viewDidLoad` (checked on macOS 26, 2026-08-27), so everything is built here.
    init() {
        super.init(nibName: nil, bundle: nil)
        splitView = GutterSplitView()
        splitView.isVertical = true
        column.splitView.isVertical = false

        let centerItem = NSSplitViewItem(viewController: center)
        centerItem.minimumThickness = ZoneSizing.minimumCenter.height
        column.addSplitViewItem(centerItem)
        column.addSplitViewItem(panelItem(.bottom))

        addSplitViewItem(panelItem(.left))
        let columnItem = NSSplitViewItem(viewController: column)
        columnItem.minimumThickness = ZoneSizing.minimumCenter.width
        addSplitViewItem(columnItem)
        addSplitViewItem(panelItem(.right))
    }

    required init?(coder: NSCoder) {
        nil
    }

    isolated deinit {
        for observation in frameObservations {
            observation.cancel()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyRoom()
        if !hasShownFirstFrame, let window = view.window {
            hasShownFirstFrame = true
            configuration?.onWindow(window)
            observeFrame(of: window)
            DispatchQueue.main.async { [weak self] in
                self?.configuration?.onFirstFrame()
            }
        }
    }

    /// layout R27: the frame is reported after a move or a resize, never during one.
    private func observeFrame(of window: NSWindow) {
        let names = [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification]
        frameObservations = names.map { name in
            let events = NotificationCenter.default.notifications(named: name, object: window).map { _ in () }
            return Task { [weak self, weak window] in
                for await _ in events {
                    guard let self, let window else { return }
                    configuration?.onWindowFrame(window.frame)
                }
            }
        }
    }

    func apply(_ configuration: Configuration) {
        self.configuration = configuration
        for gutterView in [splitView, column.splitView].compactMap({ $0 as? GutterSplitView }) {
            if gutterView.gutter != configuration.gutter {
                gutterView.gutter = configuration.gutter
            }
            if gutterView.gutterColor != configuration.windowBackground {
                gutterView.gutterColor = configuration.windowBackground
            }
        }
        // design R14, R15: the title area paints the same ground as the gutters. SwiftUI's window
        // bridge turns `titlebarAppearsTransparent` back off after the first update, which puts a
        // material band behind the toolbar (bug: 2026-08-27), so the three are re-asserted here.
        if let window = view.window {
            if window.backgroundColor != configuration.windowBackground {
                window.backgroundColor = configuration.windowBackground
            }
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }
            if window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
        }
        center.rootView = configuration.center
        for (side, slot) in slots {
            slot.show(configuration.visible[side].flatMap { id in configuration.panelView(id).map { (id, $0) } })
        }
        applyRoom()
        applyFocus(configuration.focus)
    }

    // MARK: - Room

    /// layout R20: what fits, given the room and the sizes the user chose.
    private func applyRoom() {
        guard let configuration, view.bounds.width > 0 else { return }
        let fitted = ZoneSizing.fit(
            available: view.bounds.size, requested: configuration.sizes, visible: Set(configuration.visible.keys))
        isApplying = true
        defer { isApplying = false }
        for side in PanelSide.allCases {
            guard let item = item(for: side) else { continue }
            if let size = fitted[side] {
                if item.isCollapsed {
                    item.isCollapsed = false
                }
                setThickness(size, of: side)
            } else if !item.isCollapsed {
                item.isCollapsed = true
            }
        }
    }

    private func setThickness(_ thickness: CGFloat, of side: PanelSide) {
        guard abs(currentThickness(of: side) - thickness) > 0.5 else { return }
        switch side {
        case .left:
            splitView.setPosition(thickness, ofDividerAt: 0)
        case .right:
            splitView.setPosition(splitView.bounds.width - thickness - splitView.dividerThickness, ofDividerAt: 1)
        case .bottom:
            column.splitView.setPosition(
                column.splitView.bounds.height - thickness - column.splitView.dividerThickness, ofDividerAt: 0)
        }
    }

    private func currentThickness(of side: PanelSide) -> CGFloat {
        guard let slot = slots[side] else { return 0 }
        return side == .bottom ? slot.view.frame.height : slot.view.frame.width
    }

    private func item(for side: PanelSide) -> NSSplitViewItem? {
        guard let slot = slots[side] else { return nil }
        return side == .bottom ? column.splitViewItem(for: slot) : splitViewItem(for: slot)
    }

    private func panelItem(_ side: PanelSide) -> NSSplitViewItem {
        // `slots` has every side (it is built above).
        let slot = slots[side] ?? SlotViewController()
        let item = NSSplitViewItem(viewController: slot)
        item.canCollapse = true
        item.isCollapsed = true
        item.minimumThickness = ZoneSizing.minimumPanel
        item.holdingPriority = .defaultLow + 1
        slot.onResized = { [weak self] thickness in
            self?.userResized(side, to: thickness)
        }
        return item
    }

    /// layout R18: only a drag by the user is persisted, never an adjustment to the room.
    private func userResized(_ side: PanelSide, to thickness: CGFloat) {
        guard !isApplying, let configuration, configuration.visible[side] != nil, !(view.inLiveResize),
            let item = item(for: side), !item.isCollapsed, thickness >= ZoneSizing.minimumPanel
        else { return }
        configuration.onPanelResized(side, thickness)
    }

    // MARK: - Focus

    /// layout R6: a shown panel takes the keyboard focus, the center takes it back.
    private func applyFocus(_ focus: FocusTarget) {
        guard let window = view.window else { return }
        let responder = window.firstResponder as? NSView
        switch focus {
        case .center:
            guard !Self.isFocused(center.view, responder) else { return }
            window.makeFirstResponder(center.view)
        case .panel(let id):
            guard let slot = slots.values.first(where: { $0.panelID == id }), let hosted = slot.hosted,
                !Self.isFocused(hosted.view, responder)
            else { return }
            window.makeFirstResponder(hosted.view)
        }
    }

    private static func isFocused(_ view: NSView, _ responder: NSView?) -> Bool {
        guard let responder else { return false }
        return responder === view || responder.isDescendant(of: view)
    }
}

/// One slot: shows the hosting controller of the visible panel, keeps the others (layout R5).
private final class SlotViewController: NSViewController {
    private(set) var panelID: PanelID?
    private(set) var hosted: NSHostingController<AnyView>?
    private var hostings: [PanelID: NSHostingController<AnyView>] = [:]
    var onResized: ((CGFloat) -> Void)?

    override func loadView() {
        view = ResizeReportingView()
        (view as? ResizeReportingView)?.onResized = { [weak self] size in
            guard let self, self.panelID != nil else { return }
            onResized?(size)
        }
    }

    func show(_ panel: (id: PanelID, view: AnyView)?) {
        guard panel?.id != panelID else { return }
        hosted?.view.removeFromSuperview()
        hosted?.removeFromParent()
        panelID = panel?.id
        guard let panel else {
            hosted = nil
            return
        }
        let controller = hostings[panel.id] ?? NSHostingController(rootView: panel.view)
        hostings[panel.id] = controller
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.width, .height]
        view.addSubview(controller.view)
        hosted = controller
    }
}

/// Reports its own size changes: that is how a divider drag reaches the manager.
private final class ResizeReportingView: NSView {
    var onResized: ((CGFloat) -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let previous = frame.size
        super.setFrameSize(newSize)
        guard previous != newSize, let superview = superview as? NSSplitView else { return }
        onResized?(superview.isVertical ? newSize.width : newSize.height)
    }
}

/// design R2, edge cases: a hidden panel takes its gutter with it — the divider next to a
/// collapsed item is hidden, and a hidden divider has no thickness.
class GutterSplitViewController: NSSplitViewController {
    override func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
        let items = splitViewItems
        guard dividerIndex < items.count - 1 else { return true }
        return items[dividerIndex].isCollapsed || items[dividerIndex + 1].isCollapsed
    }
}
