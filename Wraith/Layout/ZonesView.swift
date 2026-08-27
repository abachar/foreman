import AppKit
import SwiftUI

/// SwiftUI face of `ZonesViewController`: reads the manager, hands over what to show.
struct ZonesView: NSViewControllerRepresentable {
    let layout: LayoutManager
    let theme: ThemeService
    let onFirstFrame: () -> Void
    let onWindow: (NSWindow) -> Void

    func makeCoordinator() -> WorkspaceToolbar {
        WorkspaceToolbar(layout: layout, theme: theme)
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
        let theme = theme
        let tokens = theme.tokens
        return ZonesViewController.Configuration(
            visible: layout.panels.visible,
            sizes: layout.panelSizes,
            focus: layout.panels.focus,
            // design R2: the center and each panel are islands.
            center: AnyView(IslandView(theme: theme) { CenterView(layout: layout, theme: theme) }),
            panelView: { id in layout.panels.view(for: id).map { view in AnyView(IslandView(theme: theme) { view }) } },
            onPanelResized: { layout.setPanelSize($1, for: $0) },
            onFirstFrame: onFirstFrame,
            onWindow: { [toolbar = context.coordinator] window in
                if let frame = layout.windowFrame {
                    let screens = NSScreen.screens.map(\.visibleFrame)
                    let main = NSScreen.main?.visibleFrame ?? screens.first ?? frame
                    window.setFrame(LayoutManager.frameToRestore(frame, screens: screens, main: main), display: true)
                }
                layout.windowFrame = window.frame
                // design R14: one flat ground, no text title; the toolbar sits on it (R15).
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.backgroundColor = tokens.windowBackground.nsColor
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
            onWindowFrame: { layout.windowFrame = $0 },
            gutter: tokens.gutter,
            windowBackground: tokens.windowBackground.nsColor
        )
    }
}
