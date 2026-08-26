import AppKit
import SwiftUI

/// SwiftUI face of `ZonesViewController`: reads the manager, hands over what to show.
struct ZonesView: NSViewControllerRepresentable {
    let layout: LayoutManager
    let onFirstFrame: () -> Void

    func makeNSViewController(context: Context) -> ZonesViewController {
        let controller = ZonesViewController()
        controller.apply(configuration(with: context))
        return controller
    }

    func updateNSViewController(_ controller: ZonesViewController, context: Context) {
        controller.apply(configuration(with: context))
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
            onWindow: { window in
                // layout R25: no terminal surface yet (M2); the active tab's kind drives the scopes.
                layout.shortcuts.startMonitoring(window: window) {
                    (activeTabKind: layout.model.active.active?.kind, isTerminalFocused: false)
                }
            }
        )
    }
}
