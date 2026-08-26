import CoreGraphics
import Foundation

/// Sizes of the panel slots (layout R19, R20), pure so the shrink-then-hide order is testable.
nonisolated enum ZoneSizing {
    static let defaults: [PanelSide: CGFloat] = [.left: 260, .right: 320, .bottom: 240]
    static let minimumPanel: CGFloat = 160
    static let minimumCenter = CGSize(width: 300, height: 150)
    static let minimumWindow = CGSize(width: 800, height: 500)

    /// Order in which panels are shrunk, then hidden, when the window is too small (R20).
    static let sacrificeOrder: [PanelSide] = [.right, .left, .bottom]

    /// The thickness each visible slot gets in `available`; a slot absent from the result is
    /// hidden for lack of room. `requested` is never modified: sizes come back with the room.
    static func fit(available: CGSize, requested: [PanelSide: CGFloat], visible: Set<PanelSide>) -> [PanelSide: CGFloat]
    {
        var sizes: [PanelSide: CGFloat] = [:]
        for side in visible {
            sizes[side] = max(requested[side] ?? defaults[side] ?? minimumPanel, minimumPanel)
        }
        for side in sacrificeOrder where sizes[side] != nil && overflow(sizes, in: available, of: side) > 0 {
            sizes[side] = max(minimumPanel, sizes[side, default: 0] - overflow(sizes, in: available, of: side))
        }
        for side in sacrificeOrder where sizes[side] != nil && overflow(sizes, in: available, of: side) > 0 {
            sizes[side] = nil
        }
        return sizes
    }

    /// How much the axis of `side` exceeds the room, keeping the center at its minimum.
    private static func overflow(_ sizes: [PanelSide: CGFloat], in available: CGSize, of side: PanelSide) -> CGFloat {
        switch side {
        case .left, .right:
            return sizes[.left, default: 0] + sizes[.right, default: 0] + minimumCenter.width - available.width
        case .bottom:
            return sizes[.bottom, default: 0] + minimumCenter.height - available.height
        }
    }
}
