import CoreGraphics
import Foundation

/// The `layout` section of `state.json` (layout R27): everything needed to rebuild a window.
nonisolated struct LayoutState: Codable, Equatable, Sendable {
    struct TabState: Codable, Equatable, Sendable {
        let id: TabID
        let kind: String
        let title: String
        /// layout R28: the feature's own JSON, never read by the layout.
        let payload: String
    }

    struct GroupState: Codable, Equatable, Sendable {
        let id: GroupID
        let tabs: [TabState]
        let activeTab: TabID?
    }

    var tree: LayoutNode
    var groups: [GroupState]
    var activeGroup: GroupID
    var panels: [PanelSide: PanelID]
    var panelSizes: [PanelSide: CGFloat]
    var windowFrame: CGRect?
    var isToolbarVisible: Bool
}
