import Foundation
import PostgresNIO
import Testing

@testable import Wraith

/// postgres R16, edge cases: cell formatting, TSV, sorting, the binary decoders written here.
struct QueryValueTests {
    @Test func formatsEachKind() {
        #expect(QueryValue.null.displayText == "NULL")
        #expect(QueryValue.int(42).displayText == "42")
        #expect(QueryValue.double(2.5).displayText == "2.5")
        #expect(QueryValue.double(3).displayText == "3")
        #expect(QueryValue.bool(true).displayText == "true")
        #expect(QueryValue.date(Date(timeIntervalSince1970: 0), hasTime: false).displayText == "1970-01-01")
        #expect(QueryValue.date(Date(timeIntervalSince1970: 0), hasTime: true).displayText == "1970-01-01T00:00:00Z")
        #expect(QueryValue.bytes([0xDE, 0xAD]).displayText == "\\xdead")
        #expect(QueryValue.json("{\"a\":\n1}").displayText == "{\"a\": 1}")
        #expect(QueryValue.raw("{1,2}").displayText == "{1,2}")
    }

    @Test func truncatesWideCellsAndLongBytes() {
        let wide = QueryValue.text(String(repeating: "x", count: 1500))
        #expect(wide.displayText.count == 1001)
        #expect(wide.displayText.hasSuffix("…"))
        #expect(wide.fullText.count == 1500)
        let blob = QueryValue.bytes([UInt8](repeating: 1, count: 40))
        #expect(blob.displayText.hasSuffix("… (40 bytes)"))
        #expect(blob.fullText.count == 82)
    }

    @Test func prettyPrintsJSONOnDetail() {
        #expect(
            QueryValue.json("{\"b\":1,\"a\":[1,2]}").detailText == "{\n  \"a\" : [\n    1,\n    2\n  ],\n  \"b\" : 1\n}"
        )
        #expect(QueryValue.json("not json").detailText == "not json")
    }

    @Test func tsvEscapesAndEmptiesNull() {
        #expect(QueryValue.null.tsvText == "")
        #expect(QueryValue.text("a\tb\nc\\d").tsvText == "a\\tb\\nc\\\\d")
        let columns = [QueryResult.Column(name: "id", type: "int4"), QueryResult.Column(name: "n", type: "text")]
        let rows = [
            QueryResult.Row(id: 0, values: [.int(1), .text("x\ty")]), QueryResult.Row(id: 1, values: [.int(2), .null]),
        ]
        #expect(QueryResult.tsv(columns: columns, rows: rows) == "id\tn\n1\tx\\ty\n2\t")
    }

    @Test func sortsNumericallyStablyWithNullLast() {
        let rows = [
            QueryResult.Row(id: 0, values: [.int(10)]), QueryResult.Row(id: 1, values: [.null]),
            QueryResult.Row(id: 2, values: [.int(2)]), QueryResult.Row(id: 3, values: [.int(10)]),
            QueryResult.Row(id: 4, values: [.double(2.5)]),
        ]
        #expect(QueryResult.sorted(rows, by: 0, ascending: true).map(\.id) == [2, 4, 0, 3, 1])
        #expect(QueryResult.sorted(rows, by: 0, ascending: false).map(\.id) == [0, 3, 4, 2, 1])
        let texts = [QueryResult.Row(id: 0, values: [.text("b10")]), QueryResult.Row(id: 1, values: [.text("b9")])]
        #expect(QueryResult.sorted(texts, by: 0, ascending: true).map(\.id) == [1, 0])
    }

    @Test func countsPages() {
        var result = QueryResult(columns: [], rows: [], duration: .milliseconds(42))
        #expect(result.durationText == "42 ms")
        result.rows = [QueryResult.Row(id: 0, values: [])]
        #expect(result.countText == "1 row")
        result.rows = (0..<1200).map { QueryResult.Row(id: $0, values: []) }
        #expect(result.countText == "1200 rows (3 pages of 500)")
    }

    @Test func formatsTimeAndInterval() {
        #expect(QueryValue.timeOfDay(microseconds: 0) == "00:00:00")
        #expect(QueryValue.timeOfDay(microseconds: 13 * 3_600_000_000 + 5 * 60_000_000 + 7_250_000) == "13:05:07.25")
        #expect(QueryValue.interval(microseconds: 0, days: 0, months: 0) == "00:00:00")
        #expect(QueryValue.interval(microseconds: 90_000_000, days: 2, months: 14) == "1 year 2 mons 2 days 00:01:30")
        #expect(QueryValue.interval(microseconds: -1_000_000, days: 0, months: 0) == "-00:00:01")
    }

    @Test func decodesBinaryScalarsNotKnownToTheLibrary() {
        var time = ByteBuffer()
        time.writeInteger(Int64(3_600_000_000))
        #expect(QueryValue.decode(type: .time, buffer: &time) == .raw("01:00:00"))
        var money = ByteBuffer()
        money.writeInteger(Int64(-1234))
        #expect(QueryValue.decode(type: .money, buffer: &money) == .raw("-12.34"))
        var inet = ByteBuffer()
        inet.writeBytes([2, 24, 0, 4, 10, 0, 0, 1])
        #expect(QueryValue.decode(type: .inet, buffer: &inet) == .raw("10.0.0.1/24"))
        var host = ByteBuffer()
        host.writeBytes([2, 32, 0, 4, 192, 168, 1, 2])
        #expect(QueryValue.decode(type: .inet, buffer: &host) == .raw("192.168.1.2"))
        var mac = ByteBuffer()
        mac.writeBytes([0x08, 0x00, 0x2B, 0x01, 0x02, 0x03])
        #expect(QueryValue.decode(type: .macaddr, buffer: &mac) == .raw("08:00:2b:01:02:03"))
        var oid = ByteBuffer()
        oid.writeInteger(UInt32(16_384))
        #expect(QueryValue.decode(type: .oid, buffer: &oid) == .int(16_384))
    }

    @Test func decodesArraysOfKnownElements() {
        var buffer = ByteBuffer()
        buffer.writeInteger(Int32(1))
        buffer.writeInteger(Int32(1))
        buffer.writeInteger(PostgresDataType.text.rawValue)
        buffer.writeInteger(Int32(3))
        buffer.writeInteger(Int32(1))
        for element in ["a", "b c"] {
            buffer.writeInteger(Int32(element.utf8.count))
            buffer.writeString(element)
        }
        buffer.writeInteger(Int32(-1))
        #expect(QueryValue.decode(type: .textArray, buffer: &buffer) == .raw("{a,\"b c\",NULL}"))

        var ints = ByteBuffer()
        ints.writeInteger(Int32(1))
        ints.writeInteger(Int32(0))
        ints.writeInteger(PostgresDataType.int4.rawValue)
        ints.writeInteger(Int32(2))
        ints.writeInteger(Int32(1))
        for value in [Int32(7), Int32(-1)] {
            ints.writeInteger(Int32(4))
            ints.writeInteger(value)
        }
        #expect(QueryValue.decode(type: .int4Array, buffer: &ints) == .raw("{7,-1}"))
    }

    @Test func unknownTypesShowTheirNameAndHex() {
        var buffer = ByteBuffer()
        buffer.writeBytes([0x01, 0x02])
        let value = QueryValue.decode(type: PostgresDataType(99_999), buffer: &buffer)
        guard case .raw(let text) = value else {
            Issue.record("expected raw")
            return
        }
        #expect(text.hasSuffix("\\x0102"))
    }
}
