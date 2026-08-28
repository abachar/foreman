import Foundation
import Testing

@testable import Foreman

/// postgres R10, R13, R14, R19: the pure rules of running a buffer.
struct QueryExecutionTests {
    private let text = "SELECT 1;\nSELECT 2;"

    @Test func selectionWinsOverTheBuffer() {
        let statement = QueryExecution.statement(in: text, selection: NSRange(location: 10, length: 9))
        #expect(statement == QueryExecution.Statement(sql: "SELECT 2;", range: NSRange(location: 10, length: 9)))
    }

    @Test func noSelectionSendsTheWholeBuffer() {
        let statement = QueryExecution.statement(in: text, selection: NSRange(location: 3, length: 0))
        #expect(statement?.sql == text)
        #expect(statement?.range == NSRange(location: 0, length: 19))
    }

    @Test func blankBufferOrSelectionSendsNothing() {
        #expect(QueryExecution.statement(in: "  \n", selection: NSRange(location: 0, length: 0)) == nil)
        #expect(QueryExecution.statement(in: text, selection: NSRange(location: 9, length: 1)) == nil)
    }

    @Test func outOfRangeSelectionFallsBackOnTheBuffer() {
        #expect(QueryExecution.statement(in: text, selection: NSRange(location: 15, length: 10))?.sql == text)
    }

    @Test func serverPositionMapsIntoTheBuffer() {
        let sent = NSRange(location: 10, length: 9)
        #expect(QueryExecution.cursorLocation(position: 1, sent: sent, textLength: 19) == 10)
        #expect(QueryExecution.cursorLocation(position: 8, sent: sent, textLength: 19) == 17)
        #expect(QueryExecution.cursorLocation(position: 50, sent: sent, textLength: 19) == 10)
        #expect(QueryExecution.cursorLocation(position: nil, sent: sent, textLength: 19) == 10)
        #expect(QueryExecution.cursorLocation(position: 0, sent: sent, textLength: 19) == 10)
        #expect(QueryExecution.cursorLocation(position: 5, sent: sent, textLength: 12) == 12)
    }

    @Test func hintsExplainTheTwoKnownStates() {
        #expect(QueryExecution.hint(sqlState: "42601")?.contains("select the statement") == true)
        #expect(QueryExecution.hint(sqlState: "25006")?.contains("Allow writes") == true)
        #expect(QueryExecution.hint(sqlState: "42P01") == nil)
        #expect(QueryExecution.hint(sqlState: nil) == nil)
    }

    @Test func aSecondRunIsRefusedNotQueued() {
        let first = TabID()
        let running = QueryExecution.State.idle.starting(first)
        #expect(running == .running(tab: first))
        #expect(running?.starting(TabID()) == nil)
        #expect(running?.starting(first) == nil)
    }

    @Test func connectionDropsOnlyWhenTheServerStaysSilentPastTheLimit() {
        #expect(QueryExecution.shouldDropConnection(answered: false, elapsed: .seconds(5)))
        #expect(!QueryExecution.shouldDropConnection(answered: false, elapsed: .seconds(4)))
        #expect(!QueryExecution.shouldDropConnection(answered: true, elapsed: .seconds(9)))
    }

    @Test func payloadRoundtrips() {
        let payload = PostgresQueryTab.Payload(title: "Query 3", text: "SELECT 'é';\n")
        #expect(PostgresQueryTab.Payload.decode(payload.encoded()) == payload)
        #expect(PostgresQueryTab.Payload.decode("nope") == nil)
    }
}
