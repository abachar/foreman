import Testing

@testable import Foreman

/// postgres R8, R19, R20: what a query tab asks its view to do to the buffer.
@MainActor
struct PostgresQueryTabTests {
    private func makeTab() -> PostgresQueryTab {
        PostgresQueryTab(id: TabID(), title: "Query 1", text: "SELECT 1")
    }

    /// Each request is a new version: the view applies it once from its coordinator and never
    /// clears it on the tab, which would be a write to observed state during a view update.
    @Test func everyBufferRequestIsANewVersion() {
        let tab = makeTab()
        #expect(tab.pending == PostgresQueryTab.PendingEdit())

        tab.requestReplacement("SELECT 2")
        #expect(tab.pending == PostgresQueryTab.PendingEdit(version: 1, replacement: "SELECT 2"))

        tab.requestInsertion("public.users")
        #expect(tab.pending == PostgresQueryTab.PendingEdit(version: 2, insertion: "public.users"))

        tab.requestCursor(7)
        #expect(tab.pending == PostgresQueryTab.PendingEdit(version: 3, cursor: 7))
    }

    /// R19: only a failure that points somewhere moves the cursor.
    @Test func aFailureWithoutAPositionAsksForNothing() {
        let tab = makeTab()
        tab.fail(.server(message: "syntax error", sqlState: "42601", position: 8), cursor: 7)
        #expect(tab.pending == PostgresQueryTab.PendingEdit(version: 1, cursor: 7))
        #expect(tab.hint?.contains("One statement per run") == true)

        tab.fail(.cancelled, cursor: nil)
        #expect(tab.pending.version == 1)
        #expect(tab.error == "Cancelled.")
    }
}
