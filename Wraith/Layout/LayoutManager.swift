import CoreGraphics
import Foundation
import Observation

/// Owner of a window's layout: the center model, the panels, the shortcut table, the slot sizes.
///
/// Views read it and send intentions; features register through it at startup.
@Observable
@MainActor
final class LayoutManager {
    private(set) var model = LayoutModel()
    let panels = PanelManager()
    let shortcuts = ShortcutRegistry()

    /// layout R18: one persisted thickness per slot, whatever panel is shown.
    private(set) var panelSizes = ZoneSizing.defaults
    /// The room the center zone currently has; geometry (R11, R12) depends on it.
    var centerSize = CGSize(width: 1100, height: 700)

    /// Registers a panel and its toggle shortcut (layout R3, R22).
    func register(panel: PanelDescriptor) {
        guard panels.register(panel) else { return }
        shortcuts.register(
            ShortcutAction(id: panel.id.rawValue, title: panel.title, defaultShortcut: panel.defaultShortcut) {
                [panels] in
                panels.toggle(panel.id)
            })
    }

    /// The user dragged a divider (layout R18); automatic adjustments never come through here.
    func setPanelSize(_ size: CGFloat, for side: PanelSide) {
        panelSizes[side] = max(size, ZoneSizing.minimumPanel)
    }

    func update(_ change: (inout LayoutModel) -> Void) {
        change(&model)
    }
}
