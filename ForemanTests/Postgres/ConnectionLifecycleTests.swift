import Testing

@testable import Foreman

/// postgres R4: visible panels x activity x clock.
struct ConnectionLifecycleTests {
    @Test func closesWhenNoPanelIsVisible() {
        #expect(ConnectionLifecycle.action(visiblePanels: 0, isBusy: false, idle: .zero) == .close)
    }

    @Test func keepsWhileAPanelIsVisibleAndRecentlyUsed() {
        #expect(ConnectionLifecycle.action(visiblePanels: 1, isBusy: false, idle: .seconds(599)) == .keep)
    }

    @Test func closesAfterTenMinutesIdle() {
        #expect(ConnectionLifecycle.action(visiblePanels: 2, isBusy: false, idle: .seconds(600)) == .close)
    }

    @Test func aRunningExecutionAlwaysKeeps() {
        #expect(ConnectionLifecycle.action(visiblePanels: 0, isBusy: true, idle: .seconds(3600)) == .keep)
    }

    /// R4: hiding the schema panel while a statement is running must not kill it — the busy
    /// state the feature passes is the real one, not a constant.
    @Test func hidingTheLastPanelMidQueryKeepsTheConnection() {
        #expect(ConnectionLifecycle.action(visiblePanels: 0, isBusy: true, idle: .zero) == .keep)
        #expect(ConnectionLifecycle.action(visiblePanels: 0, isBusy: false, idle: .zero) == .close)
    }
}
