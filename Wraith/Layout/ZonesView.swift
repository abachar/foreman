import AppKit
import SwiftUI

/// SwiftUI face of `ZonesViewController`: reads the manager, hands over what to show.
struct ZonesView: NSViewControllerRepresentable {
    let layout: LayoutManager
    let center: AnyView
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
            center: center,
            panelView: { layout.panels.view(for: $0) },
            onPanelResized: { layout.setPanelSize($1, for: $0) },
            onFirstFrame: onFirstFrame
        )
    }
}
