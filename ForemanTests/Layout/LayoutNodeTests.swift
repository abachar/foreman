import CoreGraphics
import Foundation
import Testing

@testable import Foreman

/// The split tree (layout R7–R12) on trees of one to five groups.
struct LayoutNodeTests {
    private let a = GroupID()
    private let b = GroupID()
    private let c = GroupID()
    private let d = GroupID()
    private let e = GroupID()
    private let size = CGSize(width: 1600, height: 800)

    @Test func splitsAGroupToTheRightOrBelow() {
        let tree = LayoutNode.group(a)

        #expect(
            tree.splitting(a, .vertical, adding: b)
                == .split(orientation: .vertical, first: .group(a), second: .group(b)))
        #expect(
            tree.splitting(a, .horizontal, adding: b)
                == .split(orientation: .horizontal, first: .group(a), second: .group(b)))
        #expect(tree.splitting(c, .vertical, adding: b) == tree)
    }

    @Test func splitsANestedGroupAndKeepsReadingOrder() {
        let tree = LayoutNode.group(a).splitting(a, .vertical, adding: b).splitting(b, .horizontal, adding: c)

        #expect(tree.groups == [a, b, c])
        #expect(
            tree
                == .split(
                    orientation: .vertical,
                    first: .group(a),
                    second: .split(orientation: .horizontal, first: .group(b), second: .group(c))))
    }

    @Test func closingAGroupFoldsItsSplit() {
        let tree = LayoutNode.group(a).splitting(a, .vertical, adding: b).splitting(b, .horizontal, adding: c)

        #expect(tree.closing(c) == .split(orientation: .vertical, first: .group(a), second: .group(b)))
        #expect(tree.closing(a) == .split(orientation: .horizontal, first: .group(b), second: .group(c)))
        #expect(tree.closing(b).closing(c) == .group(a))
    }

    @Test func neverClosesTheLastGroup() {
        #expect(LayoutNode.group(a).closing(a) == .group(a))
    }

    @Test func sharesSpaceEqually() {
        let tree = LayoutNode.group(a).splitting(a, .vertical, adding: b).splitting(b, .horizontal, adding: c)

        let frames = tree.frames(in: CGRect(origin: .zero, size: size))

        #expect(frames[a] == CGRect(x: 0, y: 0, width: 800, height: 800))
        #expect(frames[b] == CGRect(x: 800, y: 0, width: 800, height: 400))
        #expect(frames[c] == CGRect(x: 800, y: 400, width: 800, height: 400))
    }

    @Test func refusesASplitBelowTheMinimumGroupSize() {
        let tree = LayoutNode.group(a).splitting(a, .vertical, adding: b)

        #expect(tree.canSplit(a, .vertical, in: size))
        #expect(!tree.canSplit(a, .vertical, in: CGSize(width: 1100, height: 800)))
        #expect(tree.canSplit(a, .horizontal, in: size))
        #expect(!tree.canSplit(a, .horizontal, in: CGSize(width: 1600, height: 250)))
    }

    @Test func findsTheNeighborWithTheLargestOverlap() {
        // a | b over c, with c split again: a | (b / (c | d)), then d / e.
        let tree = LayoutNode.group(a)
            .splitting(a, .vertical, adding: b)
            .splitting(b, .horizontal, adding: c)
            .splitting(c, .vertical, adding: d)
            .splitting(d, .horizontal, adding: e)

        #expect(tree.neighbor(of: a, .right, in: size) == b)
        #expect(tree.neighbor(of: b, .left, in: size) == a)
        #expect(tree.neighbor(of: b, .down, in: size) == c)
        #expect(tree.neighbor(of: c, .up, in: size) == b)
        #expect(tree.neighbor(of: c, .right, in: size) == d)
        #expect(tree.neighbor(of: e, .left, in: size) == c)
        #expect(tree.neighbor(of: a, .left, in: size) == nil)
        #expect(tree.neighbor(of: b, .up, in: size) == nil)
        #expect(tree.neighbor(of: e, .down, in: size) == nil)
    }

    @Test func picksTheNeighborThatSharesTheLongerEdge() {
        // a on the left; on the right, b on top of a small c/d stack.
        let tree = LayoutNode.group(a)
            .splitting(a, .vertical, adding: b)
            .splitting(b, .horizontal, adding: c)
            .splitting(c, .horizontal, adding: d)

        #expect(tree.neighbor(of: a, .right, in: size) == b)
    }

    @Test func roundtripsThroughJSON() throws {
        let tree = LayoutNode.group(a).splitting(a, .vertical, adding: b).splitting(b, .horizontal, adding: c)

        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(LayoutNode.self, from: data)

        #expect(decoded == tree)
    }
}
