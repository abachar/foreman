import CoreGraphics
import Foundation

/// Stable identity of a tab group; generated at creation and persisted (layout R13).
nonisolated struct GroupID: Hashable, Codable, Sendable {
    let uuid: UUID

    init() {
        uuid = UUID()
    }
}

/// `vertical` places the second child to the right, `horizontal` below (layout R9).
nonisolated enum SplitOrientation: String, Codable, Sendable {
    case vertical
    case horizontal
}

nonisolated enum Direction: Sendable {
    case left
    case right
    case up
    case down
}

/// The binary split tree of the center zone (layout R7): a node is a split, a leaf is a group.
///
/// Every operation is pure and returns the new tree; the tree always keeps at least one leaf
/// (R10). Geometry is computed from the tree with equal shares (R8), in a top-left origin.
nonisolated indirect enum LayoutNode: Equatable, Codable, Sendable {
    case group(GroupID)
    case split(orientation: SplitOrientation, first: LayoutNode, second: LayoutNode)

    /// layout R19: what the center zone guarantees to every group.
    static let minimumGroupSize = CGSize(width: 400, height: 200)

    /// Leaves in reading order: left before right, top before bottom.
    var groups: [GroupID] {
        switch self {
        case .group(let id):
            return [id]
        case .split(_, let first, let second):
            return first.groups + second.groups
        }
    }

    func contains(_ id: GroupID) -> Bool {
        groups.contains(id)
    }

    /// layout R9: `id` gets a sibling `new`, to its right or below (unchanged when `id` is absent).
    func splitting(_ id: GroupID, _ orientation: SplitOrientation, adding new: GroupID) -> LayoutNode {
        switch self {
        case .group(id):
            return .split(orientation: orientation, first: self, second: .group(new))
        case .group:
            return self
        case .split(let existing, let first, let second):
            return .split(
                orientation: existing,
                first: first.splitting(id, orientation, adding: new),
                second: second.splitting(id, orientation, adding: new)
            )
        }
    }

    /// layout R10: the parent split folds, the sibling takes its place (the last group stays).
    func closing(_ id: GroupID) -> LayoutNode {
        switch self {
        case .group:
            return self
        case .split(_, .group(id), let sibling), .split(_, let sibling, .group(id)):
            return sibling
        case .split(let orientation, let first, let second):
            return .split(orientation: orientation, first: first.closing(id), second: second.closing(id))
        }
    }

    /// layout R8: each split shares its rectangle equally between its children.
    func frames(in rect: CGRect) -> [GroupID: CGRect] {
        switch self {
        case .group(let id):
            return [id: rect]
        case .split(.vertical, let first, let second):
            let half = rect.width / 2
            let left = CGRect(x: rect.minX, y: rect.minY, width: half, height: rect.height)
            let right = CGRect(x: rect.minX + half, y: rect.minY, width: half, height: rect.height)
            return first.frames(in: left).merging(second.frames(in: right)) { current, _ in current }
        case .split(.horizontal, let first, let second):
            let half = rect.height / 2
            let top = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: half)
            let bottom = CGRect(x: rect.minX, y: rect.minY + half, width: rect.width, height: half)
            return first.frames(in: top).merging(second.frames(in: bottom)) { current, _ in current }
        }
    }

    /// layout, edge cases: a split is refused when both halves could not keep the minimum size.
    func canSplit(_ id: GroupID, _ orientation: SplitOrientation, in size: CGSize) -> Bool {
        guard let frame = frames(in: CGRect(origin: .zero, size: size))[id] else { return false }
        switch orientation {
        case .vertical:
            return frame.width / 2 >= Self.minimumGroupSize.width
        case .horizontal:
            return frame.height / 2 >= Self.minimumGroupSize.height
        }
    }

    /// layout R11: the adjacent group in `direction` whose frame overlaps `id` the most; on a tie,
    /// the first in reading order.
    func neighbor(of id: GroupID, _ direction: Direction, in size: CGSize) -> GroupID? {
        let frames = frames(in: CGRect(origin: .zero, size: size))
        guard let origin = frames[id] else { return nil }
        var best: (id: GroupID, overlap: CGFloat)?
        for candidate in groups where candidate != id {
            guard let frame = frames[candidate], Self.isAdjacent(frame, to: origin, direction) else { continue }
            let overlap = Self.overlap(frame, origin, direction)
            if overlap > 0, overlap > (best?.overlap ?? 0) {
                best = (candidate, overlap)
            }
        }
        return best?.id
    }

    private static func isAdjacent(_ frame: CGRect, to origin: CGRect, _ direction: Direction) -> Bool {
        let epsilon = 0.5
        switch direction {
        case .left:
            return abs(frame.maxX - origin.minX) < epsilon
        case .right:
            return abs(frame.minX - origin.maxX) < epsilon
        case .up:
            return abs(frame.maxY - origin.minY) < epsilon
        case .down:
            return abs(frame.minY - origin.maxY) < epsilon
        }
    }

    /// Length of the shared edge, on the axis perpendicular to `direction`.
    private static func overlap(_ frame: CGRect, _ origin: CGRect, _ direction: Direction) -> CGFloat {
        switch direction {
        case .left, .right:
            return max(0, min(frame.maxY, origin.maxY) - max(frame.minY, origin.minY))
        case .up, .down:
            return max(0, min(frame.maxX, origin.maxX) - max(frame.minX, origin.minX))
        }
    }
}
