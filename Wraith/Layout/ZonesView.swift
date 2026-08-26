import AppKit
import SwiftUI

/// SwiftUI face of `ZonesViewController`: reads the manager, hands over what to show.
struct ZonesView: NSViewControllerRepresentable {
    let layout: LayoutManager
    let onFirstFrame: () -> Void
    let onWindow: (NSWindow) -> Void

    func makeCoordinator() -> WorkspaceToolbar {
        WorkspaceToolbar(layout: layout)
    }

    func makeNSViewController(context: Context) -> ZonesViewController {
        let controller = ZonesViewController()
        controller.apply(configuration(with: context))
        return controller
    }

    func updateNSViewController(_ controller: ZonesViewController, context: Context) {
        controller.apply(configuration(with: context))
        context.coordinator.sync()
    }

    private func configuration(with context: Context) -> ZonesViewController.Configuration {
        let layout = layout
        return ZonesViewController.Configuration(
            visible: layout.panels.visible,
            sizes: layout.panelSizes,
            focus: layout.panels.focus,
            center: AnyView(CenterView(layout: layout)),
            panelView: { layout.panels.view(for: $0) },
            onPanelResized: { layout.setPanelSize($1, for: $0) },
            onFirstFrame: onFirstFrame,
            onWindow: { [toolbar = context.coordinator] window in
                if let frame = layout.windowFrame {
                    let screens = NSScreen.screens.map(\.visibleFrame)
                    let main = NSScreen.main?.visibleFrame ?? screens.first ?? frame
                    window.setFrame(LayoutManager.frameToRestore(frame, screens: screens, main: main), display: true)
                }
                layout.windowFrame = window.frame
                toolbar.attach(to: window)
                // layout R25: a terminal surface has the focus when it is the active tab and the
                // center has the keyboard.
                layout.shortcuts.startMonitoring(window: window) {
                    (
                        activeTabKind: layout.model.active.active?.kind,
                        isTerminalFocused: layout.isTerminalTabActive && layout.panels.focus == .center,
                        isPanelFocused: layout.panels.focus != .center
                    )
                }
                onWindow(window)
            },
            onWindowFrame: { layout.windowFrame = $0 }
        )
    }
}
