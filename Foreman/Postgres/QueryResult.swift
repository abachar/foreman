import CoreTransferable
import Foundation
import PostgresNIO

/// What a run produced (postgres R16, R17, technical options): columns, rows, timing.
nonisolated struct QueryResult: Equatable, Sendable {
    struct Column: Hashable, Sendable {
        let name: String
        /// R16: the PG type shown under the name.
        let type: String
    }

    struct Row: Identifiable, Equatable, Sendable {
        let id: Int
        let values: [QueryValue]
    }

    var columns: [Column]
    var rows: [Row]
    var duration: Duration
    var isTruncated = false

    static let pageSize = 500

    var durationText: String {
        let milliseconds = duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
        return "\(milliseconds) ms"
    }

    /// R17: `N rows (page 1/…)`.
    var countText: String {
        let pages = max(1, (rows.count + Self.pageSize - 1) / Self.pageSize)
        return rows.count == 1
            ? "1 row" : "\(rows.count) rows" + (pages > 1 ? " (\(pages) pages of \(Self.pageSize))" : "")
    }

    static func columns(of row: PostgresRow) -> [Column] {
        row.map {
            Column(name: $0.columnName, type: $0.dataType.knownSQLName?.lowercased() ?? "oid \($0.dataType.rawValue)")
        }
    }

    /// R16: stable, `NULL` last, over the loaded rows.
    static func sorted(_ rows: [Row], by column: Int, ascending: Bool) -> [Row] {
        rows.sorted { lhs, rhs in
            guard column < lhs.values.count, column < rhs.values.count else { return false }
            let order = QueryValue.compare(lhs.values[column], rhs.values[column])
            if order == .orderedSame {
                return false
            }
            if lhs.values[column] == .null || rhs.values[column] == .null {
                return order == .orderedAscending
            }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    /// R16: `cmd+c`: a header line then the rows, tab-separated.
    static func tsv(columns: [Column], rows: [Row]) -> String {
        ([columns.map(\.name).joined(separator: "\t")] + rows.map { $0.values.map(\.tsvText).joined(separator: "\t") })
            .joined(separator: "\n")
    }
}

/// What `cmd+c` puts on the pasteboard (postgres R16): the loaded rows and the selection, as
/// values.
///
/// The TSV of up to 50,000 rows is joined by the export, so it costs nothing until the
/// clipboard actually asks for it — the grid's body is evaluated at every selection click
/// (coding rules: no expensive work in a `body`).
nonisolated struct QueryClipboard: Transferable {
    let columns: [QueryResult.Column]
    let rows: [QueryResult.Row]
    /// R16: the selected row ids; empty means everything.
    let selection: Set<Int>

    /// R16: a header line then the rows, tab-separated.
    var text: String {
        QueryResult.tsv(columns: columns, rows: selection.isEmpty ? rows : rows.filter { selection.contains($0.id) })
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { (clipboard: QueryClipboard) in clipboard.text })
    }
}

/// A `Table` sort descriptor over a column index (R16: client-side sorting).
nonisolated struct QueryColumnComparator: SortComparator, Hashable, Sendable {
    let column: Int
    var order: SortOrder = .forward

    func compare(_ lhs: QueryResult.Row, _ rhs: QueryResult.Row) -> ComparisonResult {
        guard column < lhs.values.count, column < rhs.values.count else { return .orderedSame }
        let result = QueryValue.compare(lhs.values[column], rhs.values[column])
        return order == .forward ? result : result.reversed
    }
}

nonisolated extension ComparisonResult {
    fileprivate var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}
