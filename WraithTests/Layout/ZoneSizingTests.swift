import CoreGraphics
import Foundation
import Testing

@testable import Wraith

/// Room for the panels (layout R19, R20): shrink then hide in the order right, left, bottom.
struct ZoneSizingTests {
    private let requested: [PanelSide: CGFloat] = [.left: 260, .right: 320, .bottom: 240]
    private let all: Set<PanelSide> = [.left, .right, .bottom]

    @Test func keepsTheRequestedSizesWhenThereIsRoom() {
        let sizes = ZoneSizing.fit(available: CGSize(width: 1100, height: 700), requested: requested, visible: all)

        #expect(sizes == requested)
    }

    @Test func onlySizesVisibleSlotsAndFallsBackToDefaults() {
        let sizes = ZoneSizing.fit(available: CGSize(width: 1100, height: 700), requested: [:], visible: [.left])

        #expect(sizes == [.left: 260])
    }

    @Test func shrinksRightFirstThenLeft() {
        // 260 + 320 + 400 = 980: 60 pt missing come from the right panel.
        #expect(
            ZoneSizing.fit(available: CGSize(width: 920, height: 700), requested: requested, visible: all)
                == [.left: 260, .right: 260, .bottom: 240])
        // Right at its minimum (160): the next 40 pt come from the left panel.
        #expect(
            ZoneSizing.fit(available: CGSize(width: 780, height: 700), requested: requested, visible: all)
                == [.left: 220, .right: 160, .bottom: 240])
    }

    @Test func hidesRightThenLeftWhenShrinkingIsNotEnough() {
        // 160 + 160 + 400 = 720 does not fit in 700: right goes.
        #expect(
            ZoneSizing.fit(available: CGSize(width: 700, height: 700), requested: requested, visible: all)
                == [.left: 160, .bottom: 240])
        // Even one panel at its minimum does not fit: left goes too.
        #expect(
            ZoneSizing.fit(available: CGSize(width: 500, height: 700), requested: requested, visible: all)
                == [.bottom: 240])
    }

    @Test func bottomShrinksThenHidesOnItsOwnAxis() {
        #expect(
            ZoneSizing.fit(available: CGSize(width: 1100, height: 400), requested: requested, visible: all)
                == [.left: 260, .right: 320, .bottom: 200])
        #expect(
            ZoneSizing.fit(available: CGSize(width: 1100, height: 300), requested: requested, visible: all)
                == [.left: 260, .right: 320])
    }

    @Test func neverGoesUnderTheMinimumPanel() {
        let sizes = ZoneSizing.fit(
            available: CGSize(width: 1100, height: 700), requested: [.left: 10], visible: [.left])

        #expect(sizes == [.left: 160])
    }
}
